---
layout: post
title: FoundationDB 架构 - fault tolerance
mathjax: true
---

## 控制系统

控制的容灾能力建设总体可以分成两部分：key-value store 和选举。它们背后都依赖于分布式一致性协议 paxos。这里不会介绍 paxos 协议的细节，有兴趣的读者可以阅读论文《paxos made simple》。

控制系统的主体是拥有 coordinator 角色的 fdbserver，用户在使用 FoundationDB 时，会通过 fdbcli 设置几个进程作为 coordinator。Coordinator 会向其他 coordinator 发送 `CandidacyRequest`，同时每个 coordinator 会按照一定规则从多个请求中，选择出一个合适的作为 `Nonime`；最后，获得多数派（超过半数）投票的 coordinator 会成为 leader。新 leader 上任后，会定期广播心跳请求给其他节点，以抑制后者发起选举的流程；如果 leader 因为网络隔离、宕机等原因与其他节点失联，则剩余节点会再次发起选举，直至选出一个新的 leader。

// TODO: 这里可以介绍一些 coordinator 的亲和性。

除了选举外，coordinator 还会运行名叫 `GenerationReg` 的服务，后者实际上是一个有 WAL 的全内存的 key-value store，它只负责存储一种信息，clusterKey => DbState 的映射。对 `GenerationReg` 的读写请求通过 `replicateRead` 和 `replicateWrite` 实现。DbState 中记录的是事务系统的元数据。这点会在后面介绍。

coordinator 是用户手动配置的，因此如果任何一个 coordinator 宕机，都需要人工设置新的 coordinator 进行替换。而 FoudationDB 通过 fdb.cluster 记录了当前的 coordinator，并将它作为服务发现机制；为了维护服务发现机制，新 coordinator 会通过xx广播给集群中的每个节点，这些节点又更新各自的 fdb.cluster 文件，包括 client 在内（对于 client，只要有写权限，就会更新该文件）。


## 事务系统

选出来的 leader 会成为集群的 controller，它负责管理整个集群，其中就包括事务系统的容错。controller 会监控事务系统的各个节点，如果事务系统不存在或者任意一个节点被监控系统判断为失联、故障，则 controller 会触发一次事务系统的 recovery。

recovery 流程会选择合适的 fdbserver 并拉起 master, GRV proxies, commit proxies, resolvers 和新的 TLogs。recovery 的核心问题是在新旧事务系统切换时保证读写请求的一致性。

因此 recovery 的第一件事情便是冻结原 TLogs 的写入。（TODO：需要冻结多少个才算完成呢？多数派？还是一个就行？如果有任何一个节点没有被封印，那么它一直接收日志，会影响 recovery 过程中的恢复吗）

一旦 TLogs 被成功封印，原来事务系统中正在进行的事务将不会得到提交。这一点与其他的系统也是类是的，比如 facebook 的 bookkeeper，StreamNative 的 pulsar。唯一不同的是原 TLog 中剩余的那部分日志将不会被复制到新 TLog 中，这是因为 storage 会迅速的消费这部分 TLog 并持久化，最后这些 TLog 就会被回收。

读请求能读到的事务数据受 master 控制，master 需要在启动时推进事务时间戳，以保证读请求的有效性（TODO：需要进一步验证）。只要 5s 时间锅后，那么新请求也将超过 resolver 的 MVCC 窗口，因此新提交的事务也不会与原来的事务产生冲突。

另一个需要解决的问题是，client 如何观察到事务系统的变更？Proxy 在 DbInfo 中记录了 Txn 的状态，当有变更时会通过xxx广播给 client（集群中使用 client 的其他节点同理）。原来的 master 等节点是如何退场的？（一些事务无法确定其执行状态，比如一个事务已经复制给某几个 TLog，最终被 storage 拉到本地持久化，这就需要使用这自己进行重试。后面一片文章介绍）

## 存储系统

和前两个系统相比，存储系统的容错过程则简单得多。controller 会启动一个 Data Distributor 服务，后者监控集群中的副本状态，如果有一个副本失联，那么它会选择一个合适的机器，并发送 MovingShard 请求给该机器，这个新机器将会从剩余的健康机器中拉取存量数据；这个过程中它也会从 TLog 中拉取增量数据，但是增量数据会缓存在内存中，直到所有存量数据都拉取完并完成持久化。


