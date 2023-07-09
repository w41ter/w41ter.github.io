---
layout: post
title: grpc 的一些踩坑经验
mathjax: true
---

最近的工作需要对某个系统的 RPC 部分做优化。这个系统有多个组件，分别使用不同语言编写，此次我需要优化的组件分别由 java 和 c++ 编写，java 使用 grpc 访问使用 brpc 的 c++ 服务。

该系统在编写之初为了省事，将 c++ 服务放在四层负载均衡 VIP 之后，以利用其提供的负载均衡、探活熔断的能力。这种图省事的操作为系统留下了几个隐患：
1. 如果 java 组件部署数量不够，那么无法保证通过 VIP 建立的连接数能够均衡分布到每个 RS
2. 如果不重启 java 组件，那么新加入的 RS 无法获得新连接。

## 一些尝试

刚开始接受这个任务时，我的思路主要集中在能否通过简单改造 rpc 来解决前面两个问题。

针对第一个问题，我的初步思路是能否为每个 VIP 提供一些 tag，这样 grpc 在建立 channel 时，可以为某个 IP 建立多个连接，并使用 round-robin 的方式提供负载均衡。

我首先尝试编写一个 `Resolver`，它在 `DnsResolver` 的基础上，为每个 `EquivalentAddressGroup` 增加一个描述 tag 的 `Attribute`。不过很快我就发现，grpc 默认提供的 `RoundRobinLoadBalancer` 会清除所有通过 `Resolver` 返回的 `Attribute`，因此这种办法是不可行的。

那么进一步就是增加自定义的 `RoundRobinLoadBalaner`，去掉清除 tag 的逻辑。不过我并未按照这个方案实施，主要是它太复杂，且只解决了一个问题，难以说服项目负责人接受。

## 其他视角的解决办法

改造 rpc 的方案不行后，我将目光放在了修改使用 rpc 的方式上，很快我就发现从这里入手会简单许多。

在目前的代码里，java 服务会建立一个 `ManagedChannel`，并通过该 channel 访问 C++ 服务。其中 `ManagedChannel` 是通过 `NettyChannelBuilder` 创建的，其底层会为每个 `Resolver` 返回的 `EquivalentAddressGroup` 创建一个 `NettyTransport`（也就是 socket）。而阿里云、腾讯云提供的 VIP 只有一个 IP 地址，因此每个 java 服务最终只会创建一条到 C++ 服务的 socket。显然，只需要创建多个 `ManagedChannel`，就能建立多条 socket；再通过模拟 round-robin 算法，每次发起 rpc 前选择一个 channel，就能在很大程度上保证每个 RS 接收到的 rpc 请求是均衡的。

当然这只解决了第一个问题。VIP 机制下没有渠道可以获取到 RS 是否发生变更，因此只能从连接本身入手。一种方式是使用短连接，但它在每次访问时都需要创建一个 `ManagedChannel`，且并发数受限于可用端口数量，因此不是最优选择；另一种方式是为每个连接设置一段时间，超过时间后回收并重建连接，这样就保证在一段时间后就能与新加入的 RS 建立连接。

我选择使用第二种方式，为每个连接设置一段存活时间，超过时间后回收连接。grpc 协议提供了类似的支持：[A9-server-side-conn-mgt](https://github.com/grpc/proposal/blob/master/A9-server-side-conn-mgt.md)，它允许在 server 端配置每个连接的 `MAX_CONNECTION_AGE`，超过时间后 server 端会给 client 发送 `GOAWAY` 通知 client 关闭该连接。当然，这个协议只有 grpc server 才支持，而我们的 C++ 服务使用的 brpc 并没有提供类似的机制，所以我们需要自己提供类似的功能。该功能实现也比较简单，每次建立连接时，会在某个时间范围内随机选择一个值作为 deadline；每次发送 rpc 请求时，先判断 deadline 是否已经到达，如果超过了 deadline，那么会调用 `ManagedChannel.terminate()` 并重建连接。

## Connection refused 问题

在实施上述方案的过程中，我们还碰到了另一个 grpc 的问题：尽管后端 C++ 服务已经启动，java client 仍然会不时抛出 `Connection refused` 异常。

通过分析代码，我们发现 grpc netty 实现中，如果碰到了连接异常，会调用 `InternalSubChannel::scheduleBackoff`。它主要做了两件事情：
1. 在一段时间后，调用 `InternalSubChannel::startNewTransport` 重新建立连接。
2. 调用 `gotoState(ConnectivityStateInfo.forTransactionFailure(status))`，将错误信息保存到 subchannel picker 中。

而 `ManagedChannelImpl::ChannelTransportProvider::get()` 中会读取 subchannel picker 中保存的状态，如果对应的状态满足 `isWaitForReady() == false`，那么直接返回 `FaillingClientTransport`，最终抛出 `Connection refused` 异常。

也就是说，在 backoff 期间，所有在该 channel 上发起的 rpc 请求都会抛出 `Connection refused` 异常。而不幸的是：`InternalChannel.backoffPolicy` 是在 `AbstractManagedChannelImplBuilder` 中通过 `new ExponentialBackoffPolicy.Provider()` 设置的，没有提供自定义选项；而 `ExponentialBackoffPolicy` 中时间相关参数为常数，没有提供可修改选项，最大时间间隔为两分钟。显然，grpc java 的作者希望通过 backoff 来减小对 server 重连的压力，而我们则希望尽可能减少服务不可用时间。

幸运的是 `ManagedChannel` 提供了一个方法可以获取当前 channel 的状态。我们通过使用该接口，在每次请求前获取当前 channel 状态，如果是 `TRANSIENT_FAILURE`， 则关闭 channel 并重建。

