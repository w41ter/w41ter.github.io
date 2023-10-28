---
layout: post
title: FoundationDB 架构 - 只读事务
mathjax: true
---

前一篇文章介绍了 [FoundationDB 架构 - 事务数据的存储](https://mp.weixin.qq.com/s?__biz=MzU4ODgyOTg5NA==&amp;mid=2247483728&amp;idx=1&amp;sn=87b85f293fe91bc57f589a09be84b7a2&amp;chksm=fdd784f9caa00def578dfacc61ef7ba1ab31f64b87826c9f279bae385bf44022f9923e853dd6&token=1055659193&lang=zh_CN#rd) FoundationDB 数据是如何存储的。这篇文章将介绍如何从 FoundationDB 中读取已写入的数据。

![读请求路径](assets/FDB-arch-read-txn-imgs/read-path.png)

## 开启事务

同写事务相同，读事务开启时也需要先通过 GRV proxy 间接地从 master 获取已经提交事务的最大 version。因为写事务只需要将数据持久化到 TLog 就算完成，而 storage 拉取 message 的步骤并不在写事务提交的关键路径上。因此需要 client 在请求中携带上它能观察到的最大的 version，storage 才能通过这个 version 判断本地数据是否完整。

## 路由

Client 并不知道数据是如何分布在 storage 中以及每个 storage 的地址，它需要向 FoundationDB 集群查询 key 到 storage server 的路由项（称为 location）。

因为任何对 key 到 server 映射关系的变更操作都需要通过 commit proxy 持久化到 TLog 中（这部分细节将在后续的文章中介绍），所以 commit proxy 知晓整个集群的 location。Client 通过发送 `GetKeyServerLocations` 请求给 commit proxy 以查询 locations。

由于 location 变更是个低频操作，缓存 location 能够有效降低查询 commit proxy 的次数。每次发送请求前，client 都会先查询缓存，如果未命中才会向 commit proxy 请求 location；此外，如果 location 过期，那么 storage 会拒绝服务，这种情况下 client 会清理缓存，再次向 commit proxy 获取最新的 location。

## 读数据

拿到 location 后，client 会发送 `getValue` 请求给 storage。前一篇文章已经介绍了，storage 中的数据分为两部分，第一部分存在多版本窗口中，第二部分存在磁盘 key value store 中。

Storage 会先在内存中查找 key，如果未命中再从磁盘 key value 中读取。这里需要注意的是磁盘中的数据是没有版本信息的，所以无法判断这部分数据是否能够被指定版本的读请求读取到，因此如果一个请求携带的 version 已经超过了多版本窗口（默认为 5s），那么 storage 将返回 transaction too old，迫使 client 重新尝试。


另一个需要注意的情况是，如果 storage 收到请求时，还没有从 TLog 拉取到对应 version 的数据，那么 storage 会阻塞该请求，直到数据可以被访问。

到此，FoundationDB 事务的读写流程已经介绍完了。在后面的文章中，将介绍 FoundationDB 如何提供高可扩展的能力。

