---
layout: post
title: Shrinking Logs by Safely Discarding Commands
---


## Log based protocols

![Figure 1: log based protocols](/uploads/images/2022/shrinking-log-by-discarding-records-1.png)

Log 主要用于保证日志持久化、按照固定顺序复制以获得 consistent state。一个标准的 log-based protocol 需要按照一定顺序将 record 追加到 log 中，完成持久化后才响应 client。恢复时，从快照中拿到一个 index，从这个点开始回放日志，最终保证状态与恢复前一致。

## 主要设计

![Figure 2: stable](/uploads/images/2022/shrinking-log-by-discarding-records-2.png)

记录到日志中的 record 之间可能存在 overwrite，比如两个相邻的 write 操作，都更新了某个 key，那么实际上只有后一个操作需要持久化。着这个思路下，每次获取一批需要持久化的 records，将他们的更新先记录到一个 hash table 上。如果存在 overwrite 的情况，只记录下最后一个 key-value。

通过这种方式，能够减小写入到持久化设备的 record 大小，从而增加了吞吐。

这篇论文实际参考价值不大，里面涉及到的设计思路实际上在工业环境中效果不大。比如在支持 MVCC 的 key value 数据库中，更新之间基本上不存在 overwrite。一些可以 merge 的操作，也大都在写 log 前完成。不过论文的 Introduction 和 Releated Work 倒是可以当作综述阅读。
