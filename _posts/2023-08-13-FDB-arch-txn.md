---
layout: post
title: FoundationDB 架构 - 写事务处理流程
mathjax: true
---

前一篇文章 [FoundationDB 架构概述](https://mp.weixin.qq.com/s?__biz=MzU4ODgyOTg5NA==&mid=2247483697&idx=1&sn=7ad949ecc5f298b2061d1a4066e2572c&chksm=fdd78498caa00d8e8df55fa70b3b364edd0e8e688efa03dc8d1110d46a16cda455aa50b7eaf3#rd) 从全局视角介绍了 FoundationDB 架构的特点，这篇文章将介绍 FoundationDB 写事务的处理流程以及各个组件间是如何沟通协作的。

## Open Database

在与 FoundationDB 集群交互前，client 需要先执行 open database。

![Open Database](assets/FDB-arch-txn-imgs/open-database.png)

执行 open database 时，client 会从 `fdb.cluster` 文件中获取 `connection string`，后者指向了集群中的 coordinators；client 发送 `OpenDatabaseCoordRequest` 请求给 coordinator 进行验证，并获取 `ClientDBInfo`。

`ClientDBInfo` 中记录了集群中 GRV proxy 和 Commit proxy 的地址，后续的写请求会用到这两个 proxy 的地址。

## 提交事务

FoundationDB 依赖一个全局单调递增的时间戳来提供多版本并发控制。每个事务提交时，会分配一个新的版本（Version）；事务间按照 version 大小确定唯一的提交顺序。

FoundationDB 支持交互式事务，开启事务时会获取之前已经提交的最大的事务 version，并在一段时间后才会提交，所以事务间可能存在冲突。FoundationDB 通过检测事务间的 read-write confliction 来避免快照隔离（snapshot isolation, si）带来的 write skew，从而取得序列化快照隔离（serializable snapshot isolation, ssi）。

> 上述实现又称 write snapshot isolation, 出处见论文： A critique of snapshot isolation。

最后，可以提交的事务会写入 TLog 中完成持久化，再异步地发送到存储系统中。

![Commit Transaction](assets/FDB-arch-txn-imgs/commit-txn.png)

上图展示了一个写事务提交的完整交互流程，接下来将按照上图详细分析各个流程。

开启新事务时，需要确定新事务的可见范围，也就是当前事务执行时有哪些事务已经提交。为此，Client 会发送 `GetReadVersionRequest` 给 GRV proxy 以查询已经提交的最大的事务 version；后者积攒一批请求后，发送 `GetRawCommitVersionRequest` 给 Master 节点，查询记录在 Master 内存中的已经提交的最大的事务 version。

之后的任何写入操作会暂存在 client 的内存中，同时记录下读请求的范围供后续检测事务间的冲突。（读事务的处理流程将在后续的文章中介绍。）

暂存在 client 内存中的数据在提交时通过 `CommitTransactionRequest` 发送给 Commit proxy，后者将提交过程分成几个步骤：

1. 获取 commit version
2. 解决事务冲突
3. 持久化改动
4. 响应事务提交结果

### 获取 commit version

Commit proxy 积攒一批请求后，发送 `GetCommitVersionRequest` 给 Master 以获取一个新的提交 version 以及确定事务间的顺序。Master 内存中记录着上一次分配（前一个事务）的 commit version，在上一次的基础上按照时间间隔分配一个新的 version。由于 Master 分配的 version 的大小和时间也有一定关系，所以 `GetCommitVersionReply` 中会携带前一个事务的 commit version（prev commit version） 和新分配的 commit version。

拿到新 commit version 后，commit proxy 会按照顺序给这一批事务分配 versionstamp，它由两部分组成 `<commit version, group id>`，其中 group id 是事务在本批次队列中的序号。

> FoundationDB 的原子操作中支持将 key 或者 value 的某部分替换成 versionstamp，用于在 client 侧确定一个唯一的事务，分配 versionstamp 的意义就在此。

分配好 versionstamp 后，Commit proxy 会检查每个事务的改动（mutation），并替换掉其中需要设置 versionstamp 的部分 mutation。

### 解决事务冲突

Resolver 负责解决事务冲突，Commit proxy 会将事务的 read ranges 和 write ranges 以及事务的 prev commit version，commit version 一起通过 `ResolveTransactionBatchRequest` 发送给 Resolver 。

Resolver 会按照事务 version 顺序处理每个到达请求，事务间的顺序依靠 prev commit version 和 commit version 一起组织起来。如果事务与之前已经提交的事务不存在 read-write confliction，那么就可以提交；否则事务应该被拒绝。

### 持久化 mutation

解决事务间冲突后，需要将 mutations 通过 `TLogCommitRequest` 发送给 TLog 完成持久化。集群中可能有多个 TLog 实例，那么这些 mutations 会被发送给每一个 TLog，所有 TLog 完成持久化后，事务才算完成提交。（实际上 mutations 只会发送给一部分 TLog，剩余的只会发送一个空请求，这部分将在后续的文章中介绍）

如果某个事务被拒绝提交，那么它的 mutations 不会被发送到 TLog 持久化。由于 TLog 也是按照事务的 version 顺序依次持久化，所以尽管某一批事务请求都拒绝，Commit proxy 仍然需要发送 `TLogCommitRequest` 给 TLog ，这样 TLog 才能知道何时可以持久化后续的 mutations。

### 响应事务提交结果

一旦事务的 mutations 成功持久化到 TLog 后，就算完成了提交请求，但是在回复 client 前，Commit proxy 还需要发送 `ReportRawCommittedRequest` 给 Master 以更新后者内存中记录的最大的已提交事务的 version。所以，FoundationDB 保证如果 client 收到了提交事务的回复，那么它再开启的新事务一定能够读取到此前已经提交的数据。

### 异步 apply mutations

存储系统中的 Storage 会发送 `TLogPeek` 请求，从 TLog 中获取新写入的 mutations，并完成 apply。

到此为止，整个提交事务的流程就介绍完了。其中的一些细节，比如事务冲突处理、TLog 如何持久化 mutations，将在后续的文章中一一介绍。






