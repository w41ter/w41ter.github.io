---
layout: post
title: CockroachDB KV Source Code Reading Notes
---

# CockroachDB KV

## Entrance

In `pkg/cmd/cockroach.go`:

```go
func main() {
    cli.Main()
}
```

In `pkg/cli/cli.go`:

```go
cockroachCmd.AddCommand(
    startCmd,
    initCmd,
)
```

According [cockroach db manual](http://doc.cockroachchina.baidu.com/#deploy/manual-deployment/on-premises/#step-3):

```
cockroach start --join xxx
cockroach init --host <address of any node>
```

So the setup logic lie in `startCmd`, and cluster bootstrap login lie in `initCmd`.

In `pkg/cli/start.go`, command `startCmd` will invoke `runStartJoin` -> `runStart`:

```
func runStart() {
    var s *server.Server
    s, err = server.NewServer()
    s.PreStart()
    s.InitialStart()
    s.AcceptClients()
}
```

## Start Node

In `Server::NewServer`:

```go
clock = hlc.NewClock()
engines = cfg.CreateEngines()
    eng, err = storage.NewPebble(ctx, pebbleConfig)
rpcContext = rpc.NewContext()
grpcServer = newGRPCServer(rpcContext)
g = gossip.New()
distSender = kvcoord.NewDistSender()  // `pkg/kv/kvclient/kvcoord/dist_sender.go`
tcsFactory = kvcoord.NewTxnCoordSenderFactory(txnCoordSenderFactoryCfg, distSender)  // `pkg/kv/kvclient/kvcoord/txn_coord_sender_factory.go`
db = kv.NewDBWithContext(clock, dbCtx)
raftTransport = kvserver.NewRaftTransport()
stores = kvserver.NewStores()
tsDB = ts.NewDB(db, tcsFactory)
node = NewNode()
roachpb.RegisterInternalServer(grpcServer.Server, node)
kvserver.RegisterPerReplicaServer(grpcServer.Server, node.perReplicaServer)
kvserver.RegisterPerStoreServer(grpcServer.Server, node.perReplicaServer)
ctpb.RegisterSideTransportServer(grpcServer.Server, ctReceiver)
sqlServer, err := newSQLServer(ctx, sqlServerArgs)
```

In `Server::PreStart`:

```go
s.rpcContext.SetLocalInternalServer(s.node)
s.http.start()
s.externalStorageBuilder.init()
inspectEngineState = inspectEngines()   // go through engines and constructs an initState. In `pkg/server/init.go`
    storeIdent, err = kvserver.ReadStoreIdent()
serverpb.RegisterInitServer(s.grpc.Server, initServer)  // support `service Init` in `pkg/server/serverpb/init.proto`.
startListenRPCAndSQL() // only start rpc server, but initialize sql server.
configureGRPCGateway()
startRPCServer()
onInitServerReady()
state = initServer.ServeAndWait()
    // bootstrapAddresses := cfg.FilterGossipBootstrapAddress() in `newInitServerConfig`. from func (cfg *Config) parseGossipBootstrapAddresses
    s.startJoinLoop() // continuously retries connecting to nodes specified in the join list, in order to determine what the cluster ID, node ID is.
        s.attemptJoinIn()
            send JoinNodeRequest
        s.initializeFirstStoreAfterJoin()
            kvserver.InitEngines()
    state := <- s.joinCh
s.rpcContext.NodeID.set(state.NodeID)
runAsyncTask("connect-gossip")  // only log
s.gossip.Start()
    g.setAddresses(addresses)
    g.server.start()
    g.bootstrap()
    g.manage()
s.node.start()  // In `pkg/server/node.go`
s.replicationReporter.start()
s.sqlServer.preStart()
```

There are some comments in `PreStart`:

```go
// "bootstrapping problem": nodes need to connect to Gossip fairly
// early, but what drives Gossip connectivity are the first range
// replicas in the kv store. This in turn suggests opening the Gossip
// server early. However, naively doing so also serves most other
// services prematurely, which exposes a large surface of potentially
// underinitialized services. This is avoided with some additional
// complexity that can be summarized as follows:
//
// - before blocking trying to connect to the Gossip network, we already open
//   the admin UI (so that its diagnostics are available)
// - we also allow our Gossip and our connection health Ping service
// - everything else returns Unavailable errors (which are retryable)
// - once the node has started, unlock all RPCs.
```

In `Node::start`:

```go
n.storeCfg.Gossip.NodeID.set(n.nodeDescriptor.NodeID)
n.storeCfg.Gossip.SetNodeDescriptor.set(n.nodeDescriptor)
for _, e := state.initializedEngines {
    s := kvserver.NewStore(e)  // In `pkg/kv/kvserver/store.go`
    s.Start()
        // Iterate over all range descriptor, ignoring uncommitted version.
        IterateRangeDescriptorFromDisk()
            replica = newReplica()  // In `pkg/kv/kvserver/replica_init.go`
                newUnloadReplica()
                loadRaftMuLockedReplicaMuLocked()
                    lastIndex = r.stateLoader.LoadLastIndex()
            s.addReplicaInternal(replica)
        s.cfg.Transport.Listen(s.StoreID(), s)
        s.processRaft()
        s.storeRebalancer.Start() // rebalance is finished in store?
        s.startGossip()
        s.startLeaseRenewer()

    n.addStore(s)
}
n.storeCfg.Gossip.SetStorage(n.stores)
n.startGossiping(n.stopper)  // loops on a periodic ticker to gossip node-related information.
    s.GossipStore() // GossipStore broadcasts the store on the gossip network.
```

In `Server::AcceptClients`:

```go
s.sqlServer.startServerSQL()
```

### Start Store

In `pkg/kv/kvserver/store.go`:

```
Store::Start
    ReadStoreIdent
    idalloc.NewAllocator
    intentResolver.New
    makeRaftLogTruncator
    txnrecovery.NewManager
    // Iterate over all range descriptor, ignoring uncommitted version.
    IterateRangeDescriptorFromDisk()
        replica = newReplica()  // In `pkg/kv/kvserver/replica_init.go`
            newUnloadReplica()
            loadRaftMuLockedReplicaMuLocked()
                lastIndex = r.stateLoader.LoadLastIndex()
        s.addReplicaInternal(replica)
    s.cfg.Transport.Listen(s.StoreID(), s)
	s.cfg.NodeLiveness.RegisterCallback(s.nodeIsLiveCallback)
    s.processRaft()
    s.storeRebalancer.Start() // rebalance is finished in store?
    s.startGossip()
    s.startLeaseRenewer()
    s.startRangefeedUpdator()
    NewStoreRebalancer()
```

#### ID Allocator

In `pkg/kv/kvserver/store.go`:

```go
// Create ID allocators.
idAlloc, err := idalloc.NewAllocator(idalloc.Options{
    AmbientCtx:  s.cfg.AmbientCtx,
    Key:         keys.RangeIDGenerator,
    Incrementer: idalloc.DBIncrementer(s.db),
    BlockSize:   rangeIDAllocCount,
    Stopper:     s.stopper,
}
```

The `Allocator` will allocate `rangeIDAllocCount` count from `DB` with key `keys.RangeIDGenerator`.

## Bootstrap

In `pkg/cli/init.go`:

```go
func runInit() {
    c, err := NewInitClient()
    c.Bootstrap(BootstrapRequest {})
}
```

In `pkg/server/init.go`:

```go
func (s *initServer) Bootstrap() {
    state, err = s.tryBootstrap()
}

func (s *initServer) tryBootstrap() {
    return bootstrapCluster()
}
```

In `pkg/server/node.go`, function `bootstrapCluster`:

```go
kvserver.InitEngine(engine, storeIdent)
kvserver.WriteInitialClusterData() // writes initialization data to an engine. It creates system ranges (filling in meta1 and meta2) and the default zone config.
```

Question:
- When the first range was creatiation?
  In `pkg/kv/kvserver/store_init.go`:
  ```go
                desc := &roachpb.RangeDescriptor{
                        RangeID:       rangeID,
                        StartKey:      startKey,
                        EndKey:        endKey,
                        NextReplicaID: 2,
                }
                const firstReplicaID = 1
                replicas := []roachpb.ReplicaDescriptor{
                        {
                                NodeID:    FirstNodeID,
                                StoreID:   FirstStoreID,
                                ReplicaID: firstReplicaID,
                        },
                }
                desc.SetReplicas(roachpb.MakeReplicaSet(replicas))
  ```
- How to determine whether a cluster has been bootstrapped when restarting?
  1. In `Server::PreStart`, `inspectEngineState := InspectEngines()`
  2. In `InitServer::ServeAndWait`, `s.inspectEngineState.bootstrapt()`
- When to start serving ranges?
  See `Node::start` for details.
- What happen if no any join list was specified?
  Report errors

## Join Node

In `pkg/server/node.go`, function `Join()`:
```go
compareBinaryVersion()
nodeID, err := allocateNodeID()
    val, err := kv.IncrementValRetryable(ctx, db, keys.NodeIDGenerator, 1)
        db.Inc(ctx, key, inc) // pkg/kv/db.go   var db *DB
storeID, err := allocateStoreIDs()
    val, err := kv.IncrementValRetryable(ctx, db, keys.StoreIDGenerator, count)
// create liveness record, so what is the purpose of liveness record?
n.storeCfg.NodeLiveness.CreateLivenessRecord()
```

Questions:
- What happen if receives `Join` requests?
  Only check version and allocate NodeID. If a node has already bootstrapted, it won't allocate new node id again (See PreStart() for details).
- What should to do for adding new table?
  TODO
- Where is the master role for cockroachdb?
  TODO

## Add Replica on Store

In `pkg/kv/kvserver/store_create_replica.go`, function `getOrCreateReplica`:

```
getOrCreateReplica -> tryGetOrCreateReplica
    // 1. current replica is removed, go back around
    // 2. drop messages from replica we known to be too old
    // 3. the current replica need to be removed, remove it and go back around
    // 4. drop staled msg silently
    // 5. check tombstone
    newUnloadedReplica
    Store::addReplicaToRangeMapLocked
    StateLoader::SetRangeReplicaID
    Replica::loadRaftMuLockedReplicaMuLocked
```

Questions:
- When the new replica are created?
  See above.

## Raft

1. Initialize
```
Node::start
    Store::processRaft
        raftScheduler::Start
            async raftScheduler::worker
        async raftScheduler::Wait
        async raftTickLoop
        async coalescedHeartbeatsLoop
```
2. run worker, in `pkg/kv/kvserver/store_raft.go` and `pkg/kv/kvserver/replica_raft.go`.
```
raftScheduler::worker
    raftScheduler::processTick
        Replica::tick(IsLiveMap)  // `pkg/kv/kvserver/replica_raft.go`
            RawNode::ReportUnreachable(Replica.unreachablesMu.remotes)
            Replica::maybeQuiesceRaftMuLockedReplicaMuLocked
            Replica::maybeTransferRaftLeadershipToLeaseholderLocked
            RawNode::Tick
    raftScheduler::processReady
        // See below apply parts.
    raftScheduler::processRequestQueue
        Store::withReplicaForRequest
            Store::getOrCreateReplica
            Store::processRaftRequestWithReplica
                Replica::stepRaftGroup
                    Replica::withRaftGroup
                        // if internal raft group is null, try create it
                        RawNode::Step
```
3. propose
```
Node::Batch -> Node::batchInternal
    Stores::Send(BatchRequest) -> Stores::GetStore -> Store::Send   // `pkg/kv/kvserver/store_send.go`
        Clock::Update  // Advances the local node's clock  to a high water mark from all nodes with which it has interacted.
        Store::GetReplica -> Replica::Send -> Replica::sendWithoutRangeID   // `pkg/kv/kvserver/replica_send.go`
            Replica::maybeInitializeRaftGroup      // If the internal Raft group is not initialized, create it and wake the leader.
                Replica::withRaftGroupLocked
                    Replica::maybeCampaignOnWakeLocked -> Replica::campaignLocked
                        Store::enqueueRaftUpdateCheck -> raftScheduler::EnqueueRaftReady
            Replica::executeBatchWithConcurrencyRetries
                Replica::executeReadOnlyBatch
                Replica::executeReadWriteBatch     // `pkg/kv/kvserver/replica_write.go`
                    Replica::applyTimestampCache
                    Replica::evalAndPropose        // `pkg/kv/kvserver/replica_raft.go`
                        Replica::requestToProposal // `pkg/kv/kvserver/replica_proposal.go`
                            Replica::evaluateProposal -> Replica::evaluateWriteBatch
                                Replica::evaluate1PC
                                Replica::evaluateWriteBatchWithServersideRefreshes -> Replica::evaluateWriteBatchWrapper -> evaluateBatch  // `pkg/kv/kvserver/replica_evaluate.go`
                                    optimizePuts
                                    evaluateCommand
                                        batcheval.LookupCommand
                                        Command::EvalRO
                                        Command::EvalRW
                                            Put     // `pkg/kv/kvserver/batcheval/cmd_put.go`
                                                storage.MVCCPut
                                                storage.MVCCConditionalPut  // `pkg/storage/mvcc.go`
                        Replica::propose -> propBuf::Insert
            Replica::executeAdminBatch   // No interaction with the spanlatch manager or the timestamp cache.
            Replica::maybeAddRangeInfoToResponse
        // if ranges are mismatched, try to suggest a more suitable range from this store.
```
4. apply
```
Store::processReady -> Replica::HandleRaftReady -> Replica::HandleRaftReadyRaftMuLocked -> Replica::withRaftGroupLocked
    propBuf::FlushLockedWithRaftGroup   // Question: will `propBuf::Insert` signal ready queue?
    RawNode::Ready
    Replica::applySnapshot
    Task::AckCommittedEntriesBeforeApplication  // `pkg/kv/kvserver/apply/task.go`
    Replica::sendRaftMessagesRaftMuLocked       // `pkg/kv/kvserver/replica_raft.go`
    Replica::append                             // `pkg/kv/kvserver/replica_raftstorage.go`
        storage.Writer::MVCCPut                 // Writer is `Store::Engine().NewUnindexedBatch`
        Batch::Commit
    Replica::sendRaftMessagesRaftMuLocked       // `pkg/kv/kvserver/replica_raft.go`
    Task::ApplyCommittedEntries -> Task::ApplyOneBatch
        Batch::Stage(Command) -> replicaAppBatch::Stage   // `pkg/kv/kvserver/replica_application_state_machine.go`
            Replica::ShouldApplyCommand
        Batch::ApplyToStateMachine              // StateMachine::NewBatch
        AppliedCommand::AckOutcomeAndFinish
    Replica::withRaftGroupLocked
        RawNode::Advance(Ready)
        Replica::campaignLocked     // if shouldCampaignAfterConfChange: if raft leader got moved, campaign the first remaning voter.
        Store::enqueueRaftUpdateCheck  // if RawNode::HasReady
```
5. transport
API defines in `pkg/kv/kvserver/storage_services.proto`:
```proto
service MultiRaft {
    rpc RaftMessageBatch (stream cockroach.kv.kvserver.kvserverpb.RaftMessageRequestBatch) returns (stream cockroach.kv.kvserver.kvserverpb.RaftMessageResponse) {}
    rpc RaftSnapshot (stream cockroach.kv.kvserver.kvserverpb.SnapshotRequest) returns (stream cockroach.kv.kvserver.kvserverpb.SnapshotResponse) {}
    rpc DelegateRaftSnapshot(stream cockroach.kv.kvserver.kvserverpb.DelegateSnapshotRequest) returns (stream cockroach.kv.kvserver.kvserverpb.DelegateSnapshotResponse) {}
}
```

The implementation lie in `pkg/kv/kvserver/raft_transport.go`, function is `RaftTransport::RaftMessageBatch`:
```
RaftMessageBatch
    stream.Recv
    RaftTransport::handleRaftRequest
        RaftTransport::getHandler(StoreID)  // read handler of corresponding store ID
        Store::HandleRaftRequest            // `pkg/kv/kvserver/store_raft.go`: dispatches a raft message to the appropriate Replica.
            Store::HandleRaftUncoalescedRequest
                raftReceiveQueues::LoadOrCreate(RangeID)
                raftReceiveQueue::Append
            raftScheduler::EnqueueRaftRequest
    stream.Send(newRaftMessageResponse)
```

Questions:
- Where the `conditional_put` is executed?
  In file `pkg/kv/kvserver/batcheval/cmd_conditional_put.go`, it is invoked by `executeCommand`.
- What is the purpose of `CommandID`?
  The command ID is equals `makeIDKey() -> rand.Int64()`.
  ```go
  // CmdIDKey is a Raft command id. This will be logged unredacted - keep it random.
  ```

## Rebalance

In `pkg/kv/kvserver/store.go`, function `Store::Start`:

```go
NewStoreRebalancer
StoreRebalancer::Start
    // rebalanceStore iterates through the top K hottest ranges on this store and
    // for each such range, performs a lease transfer if it determines that that
    // will improve QPS balance across the stores in the cluster. After it runs out
    // of leases to transfer away (i.e. because it couldn't find better
    // replacements), it considers these ranges for replica rebalancing.
    async StoreRebalancer::rebalanceStore
        StoreRebalancer::chooseLeaseToTransfer
        replicateQueue::transferLease
        StoreRebalancer::chooseRangeToRebalance
        DB::AdminRelocateRange
```

## DB

DB is a database handle to a single cockroach cluster. A DB is safe for concurrent use by multiple goroutines.

`kv.DB` interfaces:
- Get
- GetForUpdate
- GetProto
- GetProtoTs
- Put
- PutInline
- CPut
- Inc
- Scan
- AdminSplit
- AdminMerge
- AdminRelocateRange
- AdminChangeReplicas
- etc ...

Put code path:

```
DB::Put -> DB::Run(Batch) -> DB::SendAndFail -> DB::send -> DB::sendUsingSender
    CrossRangeTxnWrapperSender::Send -> DistSender::Send
        DistSender::initAndVerifyBatch
        keys.Range
        DistSender::divideAndSendParallelCommit
            DistSender::divideAndSendBatchToRanges
        DistSender::divideAndSendBatchToRanges
            RangeIterator::Seek
            DistSender::sendPartialBatch
                DistSender::sendToReplicas
                    DistSender::transportFactory
                    Transport::SendNext
```

### Error Retry

TODO

### Range Cache

TODO

### Txn

TODO
