---
title: Raft 实现指北-日志模块
date: 2018-01-02 21:14:14
tags: 
    - Raft 
    - Consensus
    - Practice
    - Destribution
categories: Destribution
mathjax: true
---

在真正开始设计之前，需要考虑好 Raft 框架的搭建。如下图所示，一个服务器由三部分组成：共识算法、状态机以及日志系统。共识算法控制多副本之间日志的同步、广播。Raft 算法主要的工作是管理日志复制，所以在 Raft 应该有一个可操作的日志模块。

![图一：复制状态机的结构](https://camo.githubusercontent.com/ad683fbaefbc0bc0fcb31b1d6ca6ca8f715c12cd/68747470733a2f2f646e2d307830312d696f2e71626f782e6d652f726166742d254535253942254245312d30312e706e67)

# Write Ahead Log

在设计日志模块之前，需要先说说**预写式日志**（Write Ahead Log, WAL）。预写式日志通常出现在存储系统中，以保证数据的持久性[1]。WAL 的中心思想是对数据文件进行修改前，需要保证操作日志已经同步到稳定存储介质中。如果在进行操作时出现了错误导致程序崩溃，重启的程序可以通过读取日志重建原有状态。

Raft 算法中也需要 WAL 配合工作，比如领导人得知某条日志已经有超过半数的人响应，便将其应用到状态机并将其应用结果返回给客户端。状态机将数据保存在内存中，等待系统写入磁盘。此时如果发生错误，客户端的操作日志丢失，而它又接收到了应用成功的消息，便出现了不一致。

# 日志模块

```C++
struct LogHolder {
    vector<Entry> entries;
}
```

日志的存储结构可以简单如上设计，`Entry` 表示一套操作日志记录。所有已经通过 WAL 持久化的操作日志保存在 Raft 的 `LogHolder` 中做缓存。IO 操作非常耗时，在实际的项目中每次操作先进行 IO 操作，效率不高。通常考虑 Batch 操作，将结构修改为：

```C++
struct LogHolder {
    vector<Entry> entries;
    size_t stabled_to;
} 
```

这样操作日志和已经持久化的日志保存在一起，并通过 `stable_to` 区分开。这样将多个日志 `Entry` 一起写入 WAL，Batch 的方法可以提升系统整体的吞吐量，不过对于单条数据，会有部分延迟，与提升比起来是非常值得的。

当某条日志被成功复制到集群中过半数的节点中时，Raft 变认为这条日志可以被应用到状态机中，并标记这部分日志为提交状态。提交的日志采用追加的方式，那么原有数据将一直占用存储空间，而对于系统而言，已经被应用了的日志是无用的，所以 Raft 也提出了日志压缩思想。和存储系统中的日志压缩思路一致，都是通过选取某个时间点的日志创建状态机的快照，将时间点之前的日志全部丢弃。[2]

这里将上述的思想也设计到日志系统中：

```C++
// +--------------+--------------+-------------+-------------+
// | wait compact |  wait apply  | wait commit | wait stable |
// +--------------+--------------+-------------+-------------+
// ^ offset       ^ Applied      ^ committed   ^ stabled     ^ last
struct LogHolder {
    vector<Entry> entries;
    size_t offset;
    size_t last_applied;
    size_t last_committed;
    size_t last_stabled;
} 
```

`offset` 表示日志压缩后日志系统里存储的第一条日志在整个日志中的偏移。整个模块需要保证 $0 \le offset \le last\\_applied \lt last\\_committed \lt entreis.size()$。需要注意，`last_stabled` 和 `last_committed` 之前不一定存在着先后顺序，比如一个出现了网络隔离的节点在一段时间后上线，领导者将将其日志复制给该节点并告知其已经全部提交了，那么就会出现日志属于已经提交的状态，但是还未持久化。

在 Raft 论文中提到，在生成日志快照时，需要保存快照最后一条日志的 `index` 和 `term` 作为元信息。也有很多访问该元信息的需求，因此可以在 `entries` 中保留一个空白（dummy）日志作为快照元信息，那么 `offset` 完全可以被该日志项替代。

整个 `LogHolder` 只负责维护日志在内存中的缓存，提供日志追加、应用、提交、持久化以及压缩的基本功能，至于具体的操作实际由使用者负责管理。

## API 设计

API 设计是一个模块好用与否的关键，良好的 API 设计可以减少内部设计的暴露，减少模块间的耦合，同时提供最大程度的灵活性。这里希望 API 设计简单易用，接口数量少，粒度适中。

```go
type LogHolder interface {
    compactTo(to, term uint64)
    commitTo(uint64)
    applyEntries() []Entry
    stableEntries() []Entry
    term(uint64) uint64
    isUpToDate(idx, term uint64) bool
    tryAppend(idx, term, commitIdx uint64, entries []Entry) (uint64, bool)
    append(entries []Entry) uint64
    slice(lo, hi uint64) []Entry
}
```

- `compactTo`: 当应用生成了快照后，需要对冗余的日志进行压缩；
- `commitTo`: 日志复制到集群中半数节点中或跟随者接收到领导人提交日志的命令时调用，修改 `last_commit` 属性；
- `stableEntries`: 读取待持久化的日志，并将这部分日志标记为已经持久化；
- `applyEntries`: 读取待应用到状态机的日志，同时将其日志标记为已经应用；
- `term`: 返回某个日志提交到集群中的 `term`；
- `isUpToDate`: 用于判断候选人是否拥有最新的日志；
- `tryAppend`: 跟随者添加日志，会将冲突的日志丢弃；
- `append`: 领导添加日志，只有追加功能；
- `slice`: 分片

`compactTo`，`commitTo` 负责修改其只修改日志模块属性信息。`compactTo` 对日志进行压缩，其可用范围为 $[offset, last\\_applied]$，范围内的数据均已经应用到状态机中。实际上在跟随者从网络隔离中恢复或新加入集群时，领导人会选择发送日志来加速跟随者的同步，此时快照并没有落到可用范围内，或者日志与快照的元信息冲突（跟随者在一个少数派的网络中增加了很多日志），因此需要对整个日志系统进行重建。`commitTo` 只需要对 `to` 范围进行验证，修改 `last_commit` 即可。

`stableEntries` 和 `applyEntries` 不需要任何参数，根据属性设置对应的 `slice`，并返回需要持久化、应用的日志队列。

`isUpToDate` 比较给出的日志项和日志模块谁更新。根据 Raft 论文中给出了谁**比较新**的定义：如果两份日志最后的条目的任期号不同，那么任期号大的日志更加新；如果两份日志最后的条目任期号相同，那么日志比较长的那个就更加新。

`tryAppend` 是用于提交领导人复制给候选人的日志，由于网络分化或者节点的加入退出，获选人的日志可能落后、冲突于领导人提供的日志，日志模块需要对待追加的日志进行检查，并找出冲突项目并替换。

## 实现

`compactTo` 设计如下：

```go
func (holder *LogHolder) CompactTo(to, term uint64) {
	if holder.Term(to) != term || to <= holder.offset() || to > holder.lastApplied {
		// log entry conflict with exists, or less than offset, or great than applied
		// so need to rebuild log
		entries := make([]raftpd.Entry, 1)
		entries[0].Index = to
		entries[0].Term = term
		holder.entries = entries
		holder.lastApplied = to
		holder.commitIndex = to
		holder.lastStabled = to
	} else {
		offset := holder.offset()
		utils.Assert(offset <= to, "%d compact idx: %d less than first index: %d",
			holder.id, to, offset)
		holder.entries = drain(holder.entries, int(to-offset))
	}
}
```

首先检查是否存在冲突、或者没有在范围之内，都不存在才对日志队列进行压缩；否则重建日志模块，清空日志队列。因为使用了 dummy 日志项的缘故，这里也要把快照元信息作为一个 dummy log 保存。

和 `compactTo` 比起来，`commitTo` 的实现就容易得多。`commitTo` 需要保证**状态机安全性**和**领导人完全性**[2]，不能减少 `commit_index`；同时也要保证容错，即在服务器宕机恢复后数据具有一致性，每个可提交的日志需要已经持久化到本地。`commitTo` 需要保证数据范围在 $[commit_index, last\\_stabled]$ 之间。

```go
func (holder *LogHolder) CommitTo(to uint64) {
	if holder.commitIndex >= to {
		/* never decrease commit */
		return
	} else if holder.lastStabled < to {
		/* cannot commit unstable log entry */
		to = utils.MinUint64(to, holder.lastStabled)
	}

	utils.Assert(holder.lastIndex() >= to, "%d toCommit %d is out of range [last index: %d]",
		holder.id, to, holder.lastIndex())

	holder.commitIndex = to
}
```

`stableEntries` 和 `applyEntries` 需要返回待持久化或待应用的日志，同时会修改属性，将这已返回的日志标记为已持久化或已经应用。`term` 的实现比较直观，`isUpToDate` 的实现按照论文给出的定义即可。

```go
func (holder *LogHolder) IsUpToDate(idx, term uint64) bool {
	return term > holder.lastTerm() || (term == holder.lastTerm() && idx >= holder.lastIndex())
}
```

`append` 由领导人负责调用，由**领导人只附加原则**决定其只追加新日志到模块中。因为 Raft 的日志具有连续性，追加时要保证第一条追加的日志要紧接着日志模块的最后一条日志。`tryAppend` 由跟随者调用，正常情况下领导人发送的日志可以直接追加到跟随者的日志模块中。跟随者可能是新加入集群，并通过快照已经恢复到了快照所处的状态，此时也可以直接追加到日志模块里。当跟随者出现网络隔离导致日志远低于领导人复制来的第一条日志项（重新选举时），或日志项与领导人提供的存在冲突。如果第一条日志存在冲突，那么需要提醒领导人发送合适的日志；如果仅仅部分日志存在冲突，跟随者需要丢弃冲突日志，然后将领导人提供的日志追加到日志模块中（根据**日志匹配原则**），此时需要保证不能抛弃任何已经提交的日志（**状态机安全性**和**领导人完全性**）。

`tryAppend` 的第一步是找出第一个与现有日志存在冲突的日志索引，然后根据冲突索引丢弃存在冲突的日志，并返回。`tryAppend` 的返回值表示是否成功的将日志追加到系统中。Raft 论文 5.3 节提出了一个优化方式，*算法可以通过减少被拒绝的附加日志 RPCs 的次数来优化*，这里可以使用算法给出的一种优化方式：当附加日志 RPC 的请求被拒绝的时候，跟随者可以包含冲突的条目的任期号和自己存储的那个任期的最早的索引地址。因此在拒绝该追加请求时，还给领导人返回提示索引。

```go
func (holder *LogHolder) getHintIndex(prevIdx, prevTerm uint64) uint64 {
	utils.Assert(prevIdx != InvalidIndex && prevTerm != InvalidTerm,
		"%d get hint index with invalid idx or Term", holder.id)

	idx := prevIdx
	term := holder.Term(idx)
	for idx > InvalidIndex {
		if holder.Term(idx) != term {
			return utils.MaxUint64(holder.commitIndex, idx)
		}
		idx--
	}
	return holder.commitIndex
}

// findConflict return the first index which Entries[i].Term is not equal
// to holder.Term(Entries[i].Index), if all Term with same index are equals,
// return zero.
func (holder *LogHolder) findConflict(entries []raftpd.Entry) uint64 {
	for i := 0; i < len(entries); i++ {
		entry := &entries[i]
		if holder.Term(entry.Index) != entry.Term {
			if entry.Index <= holder.lastIndex() {
				log.Infof("%d found conflict at index %d, "+
					"[existing Term: %d, conflicting Term: %d]",
					holder.id, entry.Index, holder.Term(entry.Index), entry.Term)
			}
			return entry.Index
		}
	}
	return 0
}

func (holder *LogHolder) TryAppend(prevIdx, prevTerm, leaderCommittedIdx uint64,
	entries []raftpd.Entry) (uint64, bool) {
	lastIdxOfEntries := prevIdx + (uint64)(len(entries))
	if holder.Term(prevIdx) == prevTerm {
		conflictIdx := holder.findConflict(entries)
		if conflictIdx == 0 {
			/* success, no conflict */
		} else if conflictIdx <= holder.commitIndex {
			log.Panicf("%d entry %d conflict with committed entry %d",
				holder.id, conflictIdx, holder.commitIndex)
		} else {
			offset := prevIdx + 1
			holder.Append(entries[conflictIdx-offset:])
		}

		return lastIdxOfEntries, true
	} else {
		utils.Assert(prevIdx > holder.commitIndex,
			"%d entry %d [Term: %d] conflict with committed entry Term: %d",
			holder.id, prevIdx, prevTerm, holder.Term(prevIdx))

		return holder.getHintIndex(prevIdx, prevTerm), false
	}
}
```

# done 

至此，日志模块的实现就结束了。日志模块是整个 Raft 算法的基础，这里将日志模块剥离出来，并将提供一些原子方法。每个方法只干一件事，从而使分析方法正确性的分析更容易；每个方法都可以看作是纯函数，所以输入一定，输出则一定。实际上分布式程序的调试是一个非常困难的方式：

> 你的并发模型往往会成为你代码库中的病毒。你希望有细粒度的并发控制，好吧，你得到了，代码里到处都是。因此是并发导致了不确定性，而不确定性造成了麻烦。因此必须得把并发给踢出去。可是你又不能抛弃并发，你需要它。那么，你一定要禁止把并发和你的分布式状态机结合在一起。换句话说，你的分布式状态机必须成为纯函数式的。没有IO操作，没有并发，什么都没有。[3]

好的办法是将其抽象成纯函数式的，通过消息进行驱动，这样能够对程序拥有控制力，出现问题是可以完美重现，也能够跟踪定位到问题所在。从 Raft 算法的角度看，在上面的实现里，日志模块只是一个黑匣子，每个操作好比一个按钮，如果得到的不是想要的结果，那肯定是输入有问题（前提是黑匣子实现正确）。因此上面的代码很好的解开了算法和日志模块的耦合，隔离了双方的错误干扰。

# References

1. [预写式日志](https://zh.wikipedia.org/wiki/%E9%A2%84%E5%86%99%E5%BC%8F%E6%97%A5%E5%BF%97)
2. [寻找一种易于理解的一致性算法（扩展版）](https://ramcloud.atlassian.net/wiki/download/attachments/6586375/raft.pdf)
3. [分布式系统编程，你到哪一级了？](http://blog.jobbole.com/20304/)
