---
layout: post
title: FoundationDB 架构 - fault tolerance
mathjax: true
---

前两篇文章已经完整地介绍了 FoundationDB 的扩展能力，这一篇文章将介绍 FoundationDB 架构的最后一部分：FoundationDB 的容错能力。

从实现机制上讲，FoundationDB 的容错可以按照数据组织方式划分为三部分：控制系统容错、事务系统容错、存储系统容错。

![旧图，FoundationDB architecture overview](./FDB-arch-fault-tolerance-imgs/architecture.png)

## 控制系统

控制系统中参与容错的重要角色是 coordinator，分布式一致性算法 paxos 为它提供了容错能力。大多数分布式系统工作在异步、非拜占庭消息模型下，依靠多副本提供容错能力；paxos 算法解决了该模型下多副本间数据的一致性问题。在 paxos 算法的加持下，FoundationDB 在只要集群中仍有多于半数的 coordinator 节点存活时（无故障、无网络隔离），就能对外提供服务。由于 paxos 不是本文重点，所以不做更多介绍，更多关于 paxos 算法的细节可以阅读论文《paxos made simple》。

> The Paxos algorithm, when presented in plain English, is very simple.  Leslie Lamport

FoundationDB 中的 coordinator 角色是用户手动设置的，下面是一个例子：

```
user@host$ fdbcli
Using cluster file `/etc/foundationdb/fdb.cluster'.

The database is available.

Welcome to the fdbcli. For help, type `help'.
fdb> coordinators 10.0.4.1:4500 10.0.4.2:4500 10.0.4.3:4500
Coordinators changed
```

用户设置的 coordinators 会与 cluster key 一起组成集群的唯一标识，并保存到 `fdb.cluster` 文件中；client 可以通过该文件找到 coordinator 并操作 FoundationDB 集群。

### 选主

Coordinator 的第一个职责是协调并选举出一个合适的 controller 成为 leader，只有成为 leader 的 controller 才能开始工作；controller 负责管理整个 FoundationDB 集群，并使之能够对外提供服务。集群中的 controller 如果一段时间未接收到来自 leader 的心跳，则会触发新一轮选举，直到选出新的 leader 为止。

![election](./FDB-arch-fault-tolerance-imgs/election.png)

选举开始时，controller 会发送 `CandidacyRequest` 给所有 coordinator。Coordinator 会按照一定规则选择出优先级最高的 controller 作为被提名人（Nominee）并广播给 controller。当某个 controller 在一轮选举中收到超过半数节点的提名就会成为 leader。新 leader 上任后，会定期广播心跳给其余节点，以抑制后者发起新选举的流程。

### Coordinated State

Coordinator 的第二个职责是负责提供元数据的容错。

![Coordinated State](./FDB-arch-fault-tolerance-imgs/generation-reg.png)

每个 coordinator 会提供 `GenerationReg` 的读写服务，它扮演了 paxos 算法中的 acceptor 角色：对于读写请求，会各自携带一个读写 generation，而 `GenerationReg` 会记录下读写请求的 gneration，并保证了只响应请求 generation 不小于本地记录的 generation 的请求。Leader controller 则通过组件 `CoordinatedState` 读写 `GenerationReg`。`CoordinatedState` 组件扮演了 paxos 算法中的 proposal 角色，它通过 `ReplicatedWrite` 和 `ReplicatedRead` 来保证对 `GenerationRegs` 读写的线性一致性。

`GenerationReg` 和 `CoordinatedState` 一起组成了一个线性一致的 key-value store。实际上，这个 key-value store 中只存储了一条记录：`ClusterKey` => `DbCoreState`。其中 `ClusterKey` 是记录在 `fdb.cluster` 中的 `description` 和 `id`，`DBCoreState` 中则记录了事务系统的元数据，其中最核心的是 TLog 的拓扑以及数据分布。

### 服务发现

`fdb.cluster` 在 FoundationDB 中负责提供集群的服务发现。因为 coordinator 是用户手动配置的，因此如果任何一个 coordinator 宕机，都需要人工设置新的 coordinators 进行替换。当 coordinators 发生变更时，`fdb.cluster` 中记录的内容也需要同步变更。FoundationDB 的 client 会监控集群 leader 的变化，一旦发现 leader 中记录的 coordinators 与本地文件中记录的不同，则会用新的记录更新本地 `fdb.cluster` 文件。（只有 `fdb.cluster` 有读写权限时才会主动更新）

实际上 FoundationDB 也提供了一种自动配置 coordinators 的方式，只需要在 `fdbcli` 中执行下列命令即可：

```
fdb> coordinators auto
```

在该设置下，FoundationDB 如果发现某个 coordinator 出现故障，则会自动选择合适的节点组成新的 coordinators。

## 事务系统

FoundationDB 的 fdbserver 的核心逻辑在 worker 中，worker 提供了一系列 recruit 接口，用于在 worker 内启动各式各样的 actor，包括 master, TLog, storage, commit proxy, GRV proxy。worker 启动后会发送 `RegisterWorkerRequest` 将自己注册到 leader controller 中。Leader controller 负责按照用户配置启动事务系统中的各个成员，并监控后者的状态。

![recruit](./FDB-arch-fault-tolerance-imgs/recruit.png)

FoundationDB 事务系统的容错主要依靠 recovery。如果事务系统的任何一个成员被监控系统判断为失联、故障，则 controller 会触发一次事务系统的 recovery。Recovery 就是从一系列 worker 中选择合适的 worker，并 recruit 出事务系统所需要的 actors 的过程。这个过程中需要保证元数据的持久性，同时还需要保证新旧事务系统切换时的一致性。

### Lock TLogs

因为事务系统切换时旧的事务系统仍然可能在提交一些事务请求，所以 recovery 时需要锁住旧事务系统的 TLogs。这个过程中 recovery 会发送 `TLogLockRequest` 给 TLogs，收到该请求的 TLog 会拒绝后续由 commit proxy 发送的事务日志持久化请求，并返回本地记录的已提交的事务 version （`knownCommittedVersion`，KCV）和已经持久化的最大 version（`durableVersion`，DV）。一旦 TLogs 被锁住，旧事务系统中正在进行的事务将不会得到提交。这一点与其他的日志系统类似，比如 LogDevice, pulsar（它们称该步骤为 seal）。旧事务系统的元数据记录在 `CoordinatedState` 里，recovery 一开始需要先从 coordinators 中读取该数据。

实际上，FoundationDB 的写入请求需要提交给系统中的所有 TLog 完成持久化后才能返回，所以理论上只需要任何一个 TLog 响应 `TLogLockRequest`，就不会有新事务能被提交了。但是实现时还需要获取已经提交事务的进度（见下文 recovery txn 部分），所以需要等待至少 `logServers.size() - logReplicationFactor + 1` 个响应后上锁阶段才会结束。（`logReplicationFactor` 是一份日志的冗余数，上式的含义是保证每个日志至少有一个副本响应了 `TLogLockRequest`）。

> 上面的说法并不绝对，因为 FoundationDB 的 TLogs 还有一项名为 `antiQuorum` 的配置，它允许 commit proxy 在收到 `logServers.size() - antiQuorum` 个 TLog 的响应时立即返回。不过由于这项配置会损害 TLog 副本冗余度，已经不建议使用了。

### 恢复集群元数据

一旦旧事务系统被锁定，recovery 就会尝试从旧 TLogs 中读取集群的元数据，它们包括：
- `versionEpochKey`
- `configKeys`
- `tagLocalityListKeys`
- `serverTagsKey`

后两个已经在前面的文章中介绍过，`configKeys` 中记录着 FoundationDB 集群中的各项配置，`versionEpochKey` 中记录集群建立时的 unix epoch，也是整个系统的 version 0。这些元数据以及 recovery 过程中产生的状态，会作为一个事务提交到新事务系统中，这样保证新事务系统触发 recovery 时也能读到事务系统的元数据。

### Recovery txn

Recovery 要解决的另一个问题是：已经返回给用户的事务必须能在恢复后的新事务系统中读取到。回忆一下 commit proxy 处理流程的最后一部分：当所有 TLog 都完成事务持久化后，commit proxy 便能将事务已经提交的信息传递给用户。如果故障的是 TLog，那么任何小于最小 DV （Min Durable Version, MDV）的日志都有可能已经提交，并且响应给用户了。因此 MDV 就是可能已经响应用户的事务 version 的上界。这些可能已经提交的事务都需要复制到新的 TLogs，在满足用户设置的数据冗余度的同时保证系统的外部一致性。

Commit proxy 还会将已经提交的事务 version 广播给 TLogs，TLogs 会将该 version 做为 `knownCommittedVersion` 保存下来。最大的 KCV（Max Known Committed Version, MKCV）就是复制的下界。Recovery 过程中只需要将 `[MKCV+1, MDV]` 范围中的事务日志复制到新事务系统中。

![Max known committed version AND Min durable version](./FDB-arch-fault-tolerance-imgs/KCV.png)

上图是一个展示 MKCV 和 MDV 计算的例子。TLog 1 和 TLog 2 都持久化了 version 300 的事务日志，所以事务 version 300 的执行结果可能已经响应给了 client；version 400 只有 TLog 3 有，所以它一定没有被提交。因为网络隔离原因，controller 只能从 TLog 2 和 TLog 3 拿到 MDV 为 300，MKCV 为 200，因此它只需要将 version 300 对应的事务日志复制到新事务系统中并提交即可。

对于大于 MDV 的日志，将会从事务系统中丢弃。不过这部分事务日志可能已经被 storage 拉取并缓存到内存中，当 storage 观测到新 TLogs 时需要从内存中丢弃 version 大于 MDV 的事务日志。

### 恢复事务 Version

此外，为了保证分配的事务 version 是递增的，controller 会在 MDV 的基础上增加 `MAX_VERSIONS_IN_FLIGHT` 作为 `recoveryTransactionVersion` 发送给新 master，master 会在 `recoveryTransactionVersion` 的基础上开始分配新的 version。

> MAX_VERSIONS_IN_FLIGHT = 100 * VERSION_PER_SECOND
> VERSION_PER_SECOND     = 1e6

### Accept commits

在 recovery 的最后阶段，controller 会发送第一个 `ResolveTransactionBatchRequest` （`prevVersion == -1 && version == lastEpochEnd`）给所有的 resolver，从而允许 resolver 开始接受新的读写请求。同时 controller 还会将新 TLogs 元信息持久化到 `CoordinatedState` 中。到这个阶段后，事务系统就可以接受用户的写入了。

### 两种异常情况

一种异常情况是如果在 recovery 过程中发现 TLogs 中记录的元数据不足以支撑恢复流程。比如在 redundancy mode 为 `double` 时有两个 TLog 宕机，那么极有可能有一部分事务日志永久丢失了。这种情况下就需要用户使用 force recovery 进行恢复，这个过程中可能会丢失已经提交的数据。

```
fdbcli force_recovery_with_data_loss <DCID>
```

另一种异常情况时在 recovery 过程中又有旧事务系统的 TLogs 故障，导致计算出来的 KCV 回退，那么 controller 会终止本次 recovery 并启动一次新的 recovery。

### 服务发现

由于事务系统 recovery 过程中改变了事务系统成员的拓扑，无论是集群内部成员间通信，还是 client 提交读写请求，都需要及时发现服务的变更。

FoundationDB 集群内部通信时的服务发现由 controller 提供，controller 的地址来自 `fdb.cluster` 文件。集群内每个成员的地址会记录在 `ServerDBInfo` 中，比如 resolvers, commit proxies, GRV proxies；通过 `ServerDBInfo`，集群中的任何一个成员可以快速找到目标成员的地址；任何一个地址的变更都会通过 controller 广播给集群中的所有 worker。

对于 client，只有 `CoordinatedState` 完成持久化后，controller 才会将新事务系统的配置（commit proxies, GRV proxies）广播给所有 clients。

## 存储系统

和前两个系统相比，存储系统的容错过程则简单得多。Leader controller 会启动一个 Data Distributor 服务，后者监控集群中的副本状态，如果有一个副本失联，那么它会选择一个合适的 storage，并发送 `MovingShard` 请求给该 storage。收到 `MovingShard` 请求的 storage 将会从剩余的健康 storage 中拉取存量数据；这个过程中它也会从 TLog 中拉取增量数据，但是增量数据会缓存在内存中，直到所有存量数据都拉取完并完成持久化后改动才生效。

