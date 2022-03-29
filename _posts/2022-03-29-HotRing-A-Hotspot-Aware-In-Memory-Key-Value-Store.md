---
layout: post
title: HotRing - A Hotspot Aware In-Memory Key-Value Store
tags: concurrent
categories: papers
---

在 Alibaba 的生产环境中，KVS 的请求里有 50%-90% 只访问了 1% 的数据。如下图：

![Figure 1: Access ratio of different keys.](/uploads/images/2022/hotring-1.png)

实现 KVS 有很多可用的索引结构，其中 HASH 用得最多。目前的 HASH 算法并没有优化热点访问，也就是说读取一条热点数据，所付出的代价和读取其他数据是一样的。如下图，传统 HASH INDEX 结构的热点数据可能分布在 collision chaining 的任意位置。

![Figure 2: The conventional hash index structure](/uploads/images/2022/hotring-2.png)

理想情况下，查找一条数据的内存访问次数应该和它的冷热层度负相关。

![Figure 3: Expected memory accesses for an index lookup](/uploads/images/2022/hotring-3.png)

想要达到理想的情况，需要解决两个问题：
1. 检测并适应 hotspot shift
2. concurrent access

## HotRing

论文的做法是：针对问题 1，将传统哈希表中的 collision chain 替换成 ordered-ring。如果热点发生迁移，那么直接将 bucket header 指向新的热点 item 即可。针对问题 2，采用 lock-free 设计。

![Figure 4: The index structure of HotRing](/uploads/images/2022/hotring-4.png)

ordered ring 的结构如上图所示，整个 ring 首尾相连，一旦发现热点迁移，只需要将 bucket 的 header 更新到新热点 item 即可。这样做的好处是热点迁移时无需重新给 ring 上数据排序。

查找时从 header 开始，遍历整个 ring ；同时 Ring 上的数据会按照 `<tag, key>` 的顺序插入到合适的位置。这样做的目的是：
- tag 主要用来避免对 key 的比较
- 顺序则是用于查询时判断 ring 是否结束，否则查找时可能会受到并发更新操作的影响，无法判断是否已经遍历完整个 ring。

![Figure 5: Lookup Termination](/uploads/images/2022/hotring-5.png)

此外，排序还有另一个好处，根据 termination 条件，平均查找次数约为传统 collision chain 实现方式的一半。

## Hotspot Shift Identification

由于 hash 的 strongly uniformed distribution，可以认为热点数据也分布在各个 bucket 中，热点迁移识别的工作主要在 bucket 内部。

论文提出了两种识别方式：
1. random movement
2. statistical sampling 

第一种方式是每隔 R 个请求，如果第 R 个请求是 hot access，则不做任何改变；如果第 R 个请求是 cold access ，那么这个请求对应的 item 会成为新的 hot item。

这种方式是一个简单的概率实现，其缺点也非常明显：参数 R 的大小显著影响热点识别效果；如果数据访问频率分布是均匀的，或者 collision ring 中有多个热点，那么 head pointer 可能会频繁在这些热点中跳变；

另一种方式则是在 item 里记录下访问次数，根据次数选择出合适的 item 来作为新的 hot item。

## Concurrent

TODO

