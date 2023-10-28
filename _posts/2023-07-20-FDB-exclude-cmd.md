---
layout: post
title: FoundationDB exclude command
mathjax: true
---

# 背景

从[FoundationDB 源码阅读：maintenace 模式的作用](https://mp.weixin.qq.com/s?__biz=MzU4ODgyOTg5NA==&mid=2247483676&idx=1&sn=3f8175c1b2996a9690ac620e053b9034&chksm=fdd784b5caa00da338f85dc606152eda51c25bdd7c052370fdc6de3dc789fede709a6437f7fe&=873428723&=zh_CN#rd)中可知 FDB 的 `maintenance` 模式并不会主动触发 recruit 流程，如果待操作的机器上有 transaction system 的进程，那么重启操作将会引起 3~5s 的服务中断，原因是等待直到 failure detectors 判断机器故障后，cluster controller 才会触发 recruit 流程。

我们需要找到一个机制触发 recruit 流程，同时不触发任何数据迁移，使用 `exclude` 和 `maintenance` 配合是否能够取得这个目标呢？这就是本文研究的目的。

FDB 的 `exclude` 命令用于在不影响可用性和容错的情况下，从集群中临时或永久地移除机器、进程。详情参考：[removing-machines-from-a-cluster](https://apple.github.io/foundationdb/administration.html#removing-machines-from-a-cluster "removing-machines-from-a-cluster")。

# 代码分析

## 设置 exclude 选项

在 fdbcli 中输入 exclude ip:port no_wait 后，会进入 excludeCommandActor(fdbcli/ExcludeCommand.actor.cpp)；完成一系列检查后和准备后，进入 excludeSeversAndLocalities：

```c++
ACTOR Future<bool> excludeServersAndLocalities(Reference<IDatabase> db,
                                               std::vector<AddressExclusion> servers,
                                               std::unordered_set<std::string> localities,
                                               bool failed,
                                               bool force) {
    state Reference<ITransaction> tr = db->createTransaction();
    loop {
        tr->setOption(FDBTransactionOptions::SPECIAL_KEY_SPACE_ENABLE_WRITES);
        try {
            if (force && servers.size())
                tr->set(failed ? fdb_cli::failedForceOptionSpecialKey : fdb_cli::excludedForceOptionSpecialKey,
                        ValueRef());
            for (const auto& s : servers) {
                Key addr = failed ? fdb_cli::failedServersSpecialKeyRange.begin.withSuffix(s.toString())
                                  : fdb_cli::excludedServersSpecialKeyRange.begin.withSuffix(s.toString());
                tr->set(addr, ValueRef());
            }
            if (force && localities.size())
                tr->set(failed ? fdb_cli::failedLocalityForceOptionSpecialKey
                               : fdb_cli::excludedLocalityForceOptionSpecialKey,
                        ValueRef());
            for (const auto& l : localities) {
                Key addr = failed ? fdb_cli::failedLocalitySpecialKeyRange.begin.withSuffix(l)
                                  : fdb_cli::excludedLocalitySpecialKeyRange.begin.withSuffix(l);
                tr->set(addr, ValueRef());
            }
            wait(safeThreadFutureToFuture(tr->commit()))
```

severs 最终保存到 `excludedServersSpecialKeyRange` 中。注意到 transaction 设置了 `SPECIAL_KEY_SPACE_ENABLE_WRITES`，在提交给 fdbserver 前，fdbclient 会对 key value 做一些修饰。exclude 对应的 impl 为 `ExcludeServersRangeImpl`(`fdbclient/SpecialKeySpace.actor.cpp`)，完成检查后，进入 `excludeServers`(`fdbclient/ManagementAPI.actor.cpp`):

```c++
ACTOR Future<Void> excludeServers(Transaction* tr, std::vector<AddressExclusion> servers, bool failed) {
    tr->setOption(FDBTransactionOptions::ACCESS_SYSTEM_KEYS);
    tr->setOption(FDBTransactionOptions::PRIORITY_SYSTEM_IMMEDIATE);
    tr->setOption(FDBTransactionOptions::LOCK_AWARE);
    tr->setOption(FDBTransactionOptions::USE_PROVISIONAL_PROXIES);
    std::vector<AddressExclusion> excl = wait(failed ? getExcludedFailedServerList(tr) : getExcludedServerList(tr));
    std::set<AddressExclusion> exclusions(excl.begin(), excl.end());
    bool containNewExclusion = false;
    for (auto& s : servers) {
        if (exclusions.find(s) != exclusions.end()) {
            continue;
        }
        containNewExclusion = true;
        if (failed) {
            tr->set(encodeFailedServersKey(s), StringRef());
        } else {
            tr->set(encodeExcludedServersKey(s), StringRef());
        }
    }

    if (containNewExclusion) {
        std::string excludeVersionKey = deterministicRandom()->randomUniqueID().toString();
        auto serversVersionKey = failed ? failedServersVersionKey : excludedServersVersionKey;
        tr->addReadConflictRange(singleKeyRange(serversVersionKey)); // To conflict with parallel includeServers
        tr->set(serversVersionKey, excludeVersionKey);
    }
```

最终写入到 key `\xff\xff/conf/excluded/$server` 中。

## 标记 worker 为 excluded

fdbserver 的 cluster controller 在执行完 cluster recovery 后，会启动一个 actor `configurationMonitor` （`fdbserver/ClusterRecovery.actor.cpp`）监听 `excludedServersVersionKey` 的变化。一旦发生变化，则重新读取 `DatabaseConfiguration`，当其与内存中记录的 configuration 不同时触发 registration：

```c++
RangeResult results = wait(tr.getRange(configKeys, CLIENT_KNOBS->TOO_MANY));
ASSERT(!results.more && results.size() < CLIENT_KNOBS->TOO_MANY);

DatabaseConfiguration conf;
conf.fromKeyValues((VectorRef<KeyValueRef>)results);
TraceEvent("ConfigurationMonitor", self->dbgid)
    .detail(getRecoveryEventName(ClusterRecoveryEventType::CLUSTER_RECOVERY_STATE_EVENT_NAME).c_str(),
            self->recoveryState);
if (conf != self->configuration) {
    if (self->recoveryState != RecoveryState::ALL_LOGS_RECRUITED &&
        self->recoveryState != RecoveryState::FULLY_RECOVERED) {
        self->controllerData->shouldCommitSuicide = true;
        throw restart_cluster_controller();
    }

    self->configuration = conf;
    self->registrationTrigger.trigger();
}
```

另一个 actor `updateRegistration` 会等待 `registrationTrigger`，最后调用 `sendMasterRegistration` ；后者将新的 configuration 通过 `RegisterMasterRequest` 发送给 cluster controller。

Cluster controller 的 `clusterRegisterMaster`(`fdbserver/ClusterController.actor.cpp`) 负责处理 `RegisterMasterRequest` 。对于每一个 worker，cluster controller 会将其信息记录在 `WorkerInfo` 中；`WorkerInfo` 的成员 `priorityInfo` 中记录了 `isExcluded` 字段，表示是否通过 `exclude` 命令标记。`clusterRegisterMaster` 会遍历 `RegisterMasterRequest` 中携带的 configuration，并将 excluded 的 server 标记为 `isExcluded = true`:

```c++
db->fullyRecoveredConfig = req.configuration.get();
for (auto& it : self->id_worker) {
    bool isExcludedFromConfig =
        db->fullyRecoveredConfig.isExcludedServer(it.second.details.interf.addresses());
    if (it.second.priorityInfo.isExcluded != isExcludedFromConfig) {
        it.second.priorityInfo.isExcluded = isExcludedFromConfig;
        if (!it.second.reply.isSet()) {
            it.second.reply.send(
                RegisterWorkerReply(it.second.details.processClass, it.second.priorityInfo));
        }
    }
}
```

## 执行 recruit

除了标记 `isExcluded` 外，`clusterRegisterMaster` 还会启动一个 actor `doCheckOutstandingRequests`（`fdbserver/ClusterController.actor.cpp`）；后者会调用 `ClusterControllerData::betterMasterExists`：

```c++
if (self->betterMasterExists()) {
    self->db.forceMasterFailure.trigger();
    TraceEvent("MasterRegistrationKill", self->id).detail("MasterId", self->db.serverInfo->get().master.id());
}
```

`betterMasterExists` 会依次遍历 TLog, commit proxy, GRV proxy, resolver，任何一个 process 所在的 worker 的 `isExcluded` 为 `true`，都会返回 `true`：

```
if (commitProxyWorker->second.priorityInfo.isExcluded) {
    TraceEvent("BetterMasterExists", id)
        .detail("Reason", "CommitProxyExcluded")
        .detail("ProcessID", it.processId);
    return true;
}
```

最后 `forceMasterFailure` 会唤醒 `clusterWatchDatabase` ，后者做一些当前 epoch 的清理工作后，重新调用：`clusterRecoveryCore` 启动新阶段的 transaction system。

## Storage 会迁移吗？

fdbserver 还有一个 `ExclusionTracker`，它负责监听 `excludedServersVersionKey`（`fdbserver/include/fdbserver/ExclusionTracker.actor.h`)。一旦 excluded servers 发生变化，它会唤醒 ACTOR `trackExcludedServers` (`fdbserver/DDTeamCollection.actor.cpp`)；后者最终会唤醒 `DDTeamCollectionImpl::storageRecruiter`:

```c++
ACTOR static Future<Void> trackExcludedServers(DDTeamCollection* self) {
    state ExclusionTracker exclusionTracker(self->dbContext());
    loop {
        // wait for new set of excluded servers
        wait(exclusionTracker.changed.onTrigger());

        auto old = self->excludedServers.getKeys();
        for (const auto& o : old) {
            if (!exclusionTracker.excluded.count(o) && !exclusionTracker.failed.count(o) &&
                !(self->excludedServers.count(o) &&
                  self->excludedServers.get(o) == DDTeamCollection::Status::WIGGLING)) {
                self->excludedServers.set(o, DDTeamCollection::Status::NONE);
            }
        }
        for (const auto& n : exclusionTracker.excluded) {
            if (!exclusionTracker.failed.count(n)) {
                self->excludedServers.set(n, DDTeamCollection::Status::EXCLUDED);
            }
        }

        ...

        self->restartRecruiting.trigger();
    }
}
```

`storageRecruiter` 会收集信息并发送 `RecruitStorageRequest` 给 cluster controller:

```c++
std::set<AddressExclusion> exclusions;
auto excl = self->excludedServers.getKeys();
for (const auto& s : excl) {
    if (self->excludedServers.get(s) != DDTeamCollection::Status::NONE) {
        TraceEvent(SevDebug, "DDRecruitExcl2")
            .detail("Primary", self->primary)
            .detail("Excluding", s.toString());
        exclusions.insert(s);
    }
}

for (auto it : exclusions) {
    rsr.excludeAddresses.push_back(it);
}

if (!fCandidateWorker.isValid() || fCandidateWorker.isReady() ||
    rsr.excludeAddresses != lastRequest.excludeAddresses ||
    rsr.criticalRecruitment != lastRequest.criticalRecruitment) {
    lastRequest = rsr;
    fCandidateWorker =
        brokenPromiseToNever(recruitStorage->get().getReply(rsr, TaskPriority::DataDistribution));
}
```

前边设置好的 exclude 会被放到请求的 `excludeAddresses` 字段中。cluster controller 会根据请求条件过滤掉不合适的 worker（`fdbserver/include/fdbserver/ClusterController.actor.h`:`ClusterControllerData::getStorageWorker`）。收到 response 后，`storageRecruiter` 会发送 `InitialStorageRequest` 给目标进程，完成 recruit 流程。

可以发现，这个过程中并没有判断 storage process 的 failure status，而是直接发送 `RecruitStorageRequest`。那么这就意味着不能手动临时 exclude 任何一个 storage，否则都会触发数据迁移。

# 结论

通过分析，`exclude` 命令的确可以主动触发 recruit 流程，同时如果 process 上有 storage role，它还出触发 recruit storage 流程。

如果我们现在需要取得平滑升级的能力，那么需要以下几个步骤：

1. 列出所有的 process 的 role，如果目标机器上某个 process 有 transaction system 的 role （非 coordinator，非 storage），那么执行 `exclude $IP:$PORT`
2. 等到 recovery 完成后，执行 `maintenance on $zone-id`，表示禁用 storage process 的 failure detector
3. 修改配置、重启
4. 执行 `maintenance off`
5. 执行 `include $IP:$PORT`，允许 transaction system 的 role 调度回该机器


