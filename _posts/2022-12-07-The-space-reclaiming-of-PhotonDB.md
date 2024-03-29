---
layout: post
title: The space reclaiming of PhotonDB
mathjax: true
---

最近的一段时间我们分析并改进了 PhotonDB 的空间回收机制。

# Background

PhotonDB 的 page store 可以视作一个 log structured page allocator。

在实现上，它分为持久化和内存中的两部分，其中内存部分由串有序的 write buffer 组成。write buffer 是一段连续的内存空间，新的 delta page 从最后一个 write buffer 中分配。每个 delta page 均有唯一的逻辑地址，该地址按照分配次序递增；其他 page 可以通过这个逻辑地址访问到该 delta page。其中从根节点出发能访问到的 delta page 称为活跃的；当 page 更新后，相关的 delta page 将不再被访问，所以会被归还（dealloc）给 page store。

当 write buffer 的空间分配完后，其中仍活跃的 delta page 会持久化到存储设备上，保存到一个新的 page file 中。除了记录 delta page 外，Page file 还记录了一些元数据，包括 delta page 到 page id 的映射；先前生成的 page files 中已经归还（dealloc）的 delta page 的地址；每个 delta page 的在 write buffer 中的偏移。每个 page file 在内存中维护着一个数据结构：`FileMeta`，其中记录着 delta page 的逻辑地址到文件偏移的映射关系。

每个 write buffer 有一个唯一且递增的 ID，它是 delta page 的逻辑地址的组成部分：逻辑地址由 buffer id 和 delta page 在 buffer 中的偏移组成（`logical address = (buffer id << 32) | offset`）。Write buffer 转储时生成的 page file 拥有相同的 ID，因此对于任意一个逻辑地址，可以直接定位到 write buffer 或者 page file，并找到 delta page （对 page file ，还需要通过查询 `FileMeta`，找到文件偏移）。

前面提到了 page files 中还记录着已归还的 delta pages 的逻辑地址，虽然这些地址对应的数据将不再会被访问，但它们占用的磁盘空间仍然被保留着。我们称这部分空间为空白页。为了保证有足够的空间容纳新写入的数据，这些具有空白页的 page files 需要被整理，释放出空白页占据的空间。找到合适的 page files 并进行过程称为空间回收。

# Framework

空间回收实现时需要回答三个问题，何时进行？最优化目标？处理方法？这三个问题勾勒出空间回收机制实现的基本轮廓：
1. 空间回收触发时机
2. 候选 page file 的选择策略
3. page file 的处理方法

当某些指标达到触发条件时，使用选择策略选择出候选 page files，并对 page file 按照某种方法进行处理，最终释放出空闲空间。后文将按照顺序，依次介绍 PhotonDB 解决这三个问题的方案。

## Trigger

首先讨论的是空间回收的触发机制。PhotonDB 关注两个指标：1、使用空间；2、空间放大。在使用空间超过高水位线或者空间放大超过上限时，PhotonDB 触发空间回收，直到相关指标落到阈值下。为使用空间设置水位线，用于保证在剩余空间的比例；为空间放大设置上线，用于将整体的回收代价均摊到程序的整个运行时间段上。当然，只有存在过期 delta page 时，才能释放出空闲空间；因此只有拥有可回收空间时，使用空间的指标才会生效。

## Efficient strategy

空间回收需要占用 IO 资源，它需要重定位候选 page files 中的活跃 delta page。这个过程的开销与过期 delta page 的数量有关系。显然过期的 delta page 越多，重定位的 IO 开销就越小。

候选文件选择策略的目标就是找到最适合回收的 page files，使得总的 IO 开销最小。

### Minimize of IO cost

为了找到这样的一个策略，我们不妨假设某个 page file $i$ 在时刻 $t_n$ 被回收的代价为 $C_i$，回收成本的下降速率（decline rate）为 $\frac{dc_i(t_0)}{dt}$；如果某个时间点 $t_0$ 回收成本为 $C_0$，那么对任意未来的时间 $t$，回收该 page file 的成本为：

$C_i(t) \approx C_i(t_0) + \frac{dc_i(t_0)}{dt} (t - t_0)$

假设有 $k$ 个 page file，每次处理一个，那么总的成本为：

$Cost = \sum_{i=1}^{k} c_i(t_0) - \sum_{i=1}^{k}-\frac{dc_i(t_0)}{dt}(t_i-t_0)$

观察发现，上述公式后半部分的值越大，最终的成本越小。显然当 $-\frac{dc_i(t_0)}{dt}$ 按照顺序排列时，后半部分的值越大。因此，优先处理 decline rate 最小的 page files，最后处理 decline rate 最大的 page files，总的代价最小。

我们把上述公式给出的回收策略称为 Min Decline Rate 策略。它显然符合直觉：如果成本能在未来一段时间内大幅下降，那么等待一段时间再处理是值得的。

### Decline rate

有了理论指导后，下一步是为每个 page file 计算 decline rate。假设一个 page file 中空白页占比为 $E$，那么回收一个文件的空间，需要回收 $1/E$ 个有空闲页的 page file。其中放大部分为 $1/E(1-E)$。那么，写一个 page file 的 IO 成本为：

$Cost = \frac{1}{E} reads + \frac{1}{E} (1-E) writes + 1 = \frac{2}{E}$

进一步，IO 成本的 decline rate 为：

$\frac{d(Cost)}{dt} = (\frac{-2}{E^2})(\frac{dF}{du}) \approx \frac{−2(1 − E)}{E^2}f\Delta E$

其中 $f$ 是每个 page 的更新频率，$\Delta E$ 是每次更新时 $E$ 的变化率。文件的更新频率为 $f$ 乘上活跃 page 数。

每个 page 的更新频率可以通过如下方式估计：

$f = \frac{2}{t_{now}-t_{up2}}$

其中 $t_{up2}$ 表示倒数第二次更新某个 page 时的逻辑时间。

Min Decline Rate 策略来自于论文：[Efficiently Reclaiming Space in a Log Structured Store][decline-rate-paper-url]，如果对推导过程感兴趣，可以参考原论文。PhotonDB 使用 Min Decline Rate 作为候选 page files 选择策略。每次进行空间回收时，使用上面的公式计算每个 page file 的 decline rate 并排序。除了成本的计算外，原论文还指出，回收过程中可以使用更新频率对 delta page 进行分类，进一步降低回收成本。

[decline-rate-paper-url]: https://arxiv.org/abs/2005.00044

## Reclaim file

处理候选 page file 时，需要保证活跃的 delta page 在处理完成后仍然能够访问。由于不考虑原地更新，那么回收一个 page file 就要求实现将其中仍活跃的 delta page 复制到其他位置。

最直接的办法是将 delta page 复制到一块新开辟的空间里，同时更新对 delta page 的引用，将其指向复制后的位置。这个过程我们称为重定向，它有一个明显的缺陷：更换了 delta page 的逻辑地址。每个活跃的 delta page 均可从根节点访问到，对它的引用可能存在于 page table 中，也可能存在于同一 delta chain 上的前驱节点；对于后者，更换逻辑地址意味着需要遍历整个 delta chain，找到对应的前驱节点进行替换。对于 immutable 的数据结构而言，替换就意味着需要引入一种新的 delta page，它负责将原逻辑地址映射到新的逻辑地址上。

为了避免额外的复杂度，0.2 版本的 PhotonDB 使用了 page rewriting 的机制来避免上述问题。

### Problem with page rewriting

PhotonDB 使用的 page rewriting 机制类似于 consolidation 操作，因此它们能够复用一些逻辑。consolidation 会将 delta chain 合并，并使用生成的 delta page 替换掉 delta chain。

page rewriting 与 consolidation 略有不同，主要分两个方面：
1. page rewriting 仍然有重定位的作用，即使 delta chain 长度为 1，页需要生成新的 delta page 并替换。
2. page rewriting 可能会生成一条 delta chain，而不是一个 delta page。比如 split delta 在没有应用到父节点前，不能被合并到新 delta page 中。

Page rewriting 机制的缺点也是明显的，合并 delta chain 的过程中有大量的 IO 扇入扇出。Page rewriting 的另一个问题是没有跟踪这些新 delta page 的更新频率。与论文中的做法不同，出于性能考虑 PhotonDB 只跟踪了 page file 的更新频率，没有跟踪 delta page 的更新频率。这些 rewriting 生成的 delta page 被当作全新的写入，与用户写入的 delta page 混合到一起，导致了更新频率的失真。

### Solution

如果我们引入一层全局的转换层，它负责将逻辑地址中的 page file ID 映射到物理地址（文件，偏移）上，那么也可以做到不修改 delta page 的逻辑地址的同时回收 page file。显然这个转换层已经存在了，它就是前面提到的 FileMeta。因此，我们只需要将活跃的 delta page 复制到新的文件中，并修改 FileMeta 中的映射，就完成了 page file 的回收。

不过随着归还的 delta page 越来越多，新文件会越来越小、越来越碎片化，需要付出更大的开销来维护这些小文件的元数据；同时 IO 的预取、批处理等效率也有较低。为此，我们引入了一种新的文件格式：mapping file。Mapping file 将多个 page files 中活跃的 delta page 打包到一个文件中，同时记录下逻辑地址与物理地址的映射关系。

除了减少碎片化、避免 page rewriting 引入的 IO 放大外，mapping file 提供了提到的按照更新频率对 delta page 分类的能力；将更新频率接近的 delta page 放到一起，可以达到冷热分离的效果。从实验数据上看，mapping file 的引入，让 0.3 版本的 PhotonDB 在 zipfan 和 uniform workload 下较前一个版本分别减少了 ~5 倍和 ~2.5 倍的写放大。

