---
title: Linear Scan Register Allocation
date: 2016-09-06 23:32:12
tags: Compile
---

# 概述

图着色和线性扫描算法是常见的寄存器分配算法。其中图着色分配效果最好，但是分配效率不高，而线性扫描算法虽然非最优解，但生成结果并不比图着色差多少，且效率远远高于图着色寄存器分配方法。

<!-- more -->

# 介绍

线性扫描寄存器分配方法是对变量(VR)的活跃期间(Live Interval)为单位分配的。

# 原始分配方法

原始的Poletto等人的论文中给出了线性扫描寄存器分配方法的最基本方式：

1、使用数据流分析方法计算出每个变量(VR)的活跃期间[start, end]

2、遍历整个区间序列进行寄存器分配，这里需要引入两个辅助集合，**Active** 和 **Unhandled List**，**Unhandled List** 表示还未进行分配的区间，以 start 递增的顺序组成链式序列。****Active** 表示包含当前点且已经分配了寄存器的区间，其中的区间都按照 end 递增的方式排序。

3、当每次扫描到一个区间的时候，首先将 **Active** 集合中不再包含当前点的区间移除，并把其占用寄存器设置为未使用；判断还有没有空闲寄存器，如果有，则分配一个寄存器，并将该区间移入 **Active** 集合，否则将区间溢出(Spill)到栈上。溢出是指从 **active** 列表的最后一个区间和当前区间中选择一个，将其溢出到栈槽(stack slot)中，选择的方法就是看谁的结束位置更迟，该场景下也就是谁的结束位置更大。

```
LinearScanRegisterAllocation 
active ←{} 
foreach live interval i, in order of increasing start point 
    ExpireOldIntervals(i) 
    if length(active)=R then 
        SpillAtInterval(i) 
    else 
        register[i] ←a register 
        removed from pool of free registers 
        add i to active, sorted by increasing end point

ExpireOldIntervals(i) 
foreach interval j in active, in order of increasing end point 
    if endpoint[j] ≥ startpoint[i] then 
        return 
    remove j from active 
    add register[j] to pool of free registers

SpillAtInterval(i) 
spill ← last interval in active 
if endpoint[spill] > endpoint[i] then 
    register[i] ← register[spill] 
    location[spill] ← new stack location 
    remove spill from active 
    add i to active, sorted by increasing end point 
else 
    location[i] ← new stack location
```

其中需要注意的是 Spill 操作，其本质表示直接把该 VR 映射到 Stack Slot 中，并不为其分配寄存器，需要使用的时候才加载到寄存器。这中间可能有许多迷惑性的细节，具体可以参考[Register allocation and spilling, the easy way?](http://stackoverflow.com/questions/1960888/register-allocation-and-spilling-the-easy-way)和[Register Allocation in Compilers](http://stackoverflow.com/questions/30512879/register-allocation-in-compilers)

这里以一个例子来讲解线性扫描方法：

```
a = 1           live {a}
b = 1           live {a b}
c = a + b       live {a b c}
d = 1           live {b d a}
c = b + d + a   live {c}
```

根据上面代码可以得到区间如下：

```
a[1, 4], b[2, 3], c[3, 5], d[4, 4]
```

排序后得到序列 `a b c d` 以此分配寄存器，这里假设只有三个可用寄存器，a b c 各自占用一个寄存器，当开始分配 d 的时候，需要在 a 和 d 中选择一个溢出，此时溢出 d。

# 利用活跃区间间隙改进

上面我们发现其实 c 的区间可以分为 [3, 3] 和 [5, 5] 两个小区间，如果可以利用这中间的空隙 (lifetime hole)，那么可以减少栈溢出次数。

下面就以论文2中使用的改进方法来理解，这种方法是在 CFG 形式下做的寄存器分配，所以会和上面的有点差别。

该方法同样需要计算活性区间，计算方法如下：

1. 首先将 CFG 线性化，这里就涉及到为基本块(Basic Block)排序操作

```
COMPUTE_BLOCK_ORDER  
append first block of method to work_list  
while work_list is not empty do   
    BlockBegin b = pick and remove first block from work_list   
    append b to blocks   
    for each successor sux of b do    
        decrement sux.incoming_forward_branches    
        if sux.incoming_forward_branches = 0 then     
            sort sux into work_list    
        end if  
    end for  
end while
```

2. 为排好序的基本块中代码设置好操作数编号，这里每个操作数都加上了2，方便以后在两个操作数之间插入其他操着数

```
NUMBER_OPERATIONS  
int next_id = 0  
for each block b in blocks do   
    for each operation op in b.operations do    
        op.id = next_id    
        next_id = next_id + 2   
    end for  
end for 
```

3. 计算 Local live set

```
COMPUTE_LOCAL_LIVE_SETS  
LIR_OpVisitState visitor // used for collecting all operands of an operation  
for each block b in blocks do   
    b.live_gen = { }   
    b.live_kill = { }   
    for each operation op in b.operations do    
        visitor.visit(op)    
        for each virtual register opr in visitor.input_oprs do     
            if opr ∉ block.live_kill then 
                b.live_gen = b.live_gen ∪ { opr }    
        end for    
        for each virtual register opr in visitor.temp_oprs do     
            b.live_kill = b.live_kill ∪ { opr }    
        end for    
        for each virtual register opr in visitor.output_oprs do     
            b.live_kill = b.live_kill ∪ { opr }    
        end for   
    end for  
end for 
```

4. 计算 Global live set

```
COMPUTE_GLOBAL_LIVE_SETS  
do   
    for each block b in blocks in reverse order do    
        b.live_out = { }
        for each successor sux of b do
            b.live_out = b.live_out ∪ sux.live_in    
        end for    
        b.live_in = (b.live_out – b.live_kill) ∪ b.live_gen   
    end for  
while change occurred in any live set 
```

5. 根据上面计算的集合建立活性区间

```
BUILD_INTERVALS  
LIR_OpVisitState visitor; // visitor used for collecting all operands of an operation  
for each block b in blocks in reverse order do   
    int block_from = b.first_op.id   
    int block_to = b.last_op.id + 2   
    for each operand opr in b.live_out do     
        intervals[opr].add_range(block_from, block_to)   
    end for   
    for each operation op in b.operations in reverse order do    
        visitor.visit(op)    
        if visitor.has_call then     
            for each physical register reg do      
                intervals[reg].add_range(op.id, op.id + 1)     
            end for    
        end if    
        for each virtual or physical register opr in visitor.output_oprs do     
            intervals[opr].first_range.from = op.id     
            intervals[opr].add_use_pos(op.id, use_kind_for(op, opr))    
        end for    
        for each virtual or physical register opr in visitor.temp_oprs do     
            intervals[opr].add_range(op.id, op.id + 1)     
            intervals[opr].add_use_pos(op.id, use_kind_for(op, opr))    
        end for    
        for each virtual or physical register opr in visitor.input_oprs do     
            intervals[opr].add_range(block_from, op.id)     
            intervals[opr].add_use_pos(op.id, use_kind_for(op, opr))    
        end for   
    end for  
end for 
```

这样，建立的区间就包含 lifetime hole 信息，然后可以开始寄存器分配了。

```
WALK_INTERVALS  
unhandled = list of intervals sorted by increasing start point  
active = { }  
inactive = { }  // note: new intervals may be sorted into the unhandled list during 

// allocation when intervals are split  
while unhandled ≠ { } do   
    current = pick and remove first interval from unhandled   
    position = current.first_range.from 

    // check for intervals in active that are expired or inactive   
    for each interval it in active do    
        if it.last_range.to < position then     
            move it from active to handled    
        else if not it.covers(position) then     
            move it from active to inactive    
        end if   
    end for   

    // check for intervals in inactive that are expired or active   
    for each interval it in inactive do    
        if it.last_range.to < position then     
            move it from inactive to handled    
        else if it.covers(position) then     
            move it from inactive to active    
        end if   
    end for   
    
    // find a register for current   
    TRY_ALLOCATE_FREE_REG   
    if allocation failed then    
        ALLOCATE_BLOCKED_REG   
    end if   
    
    if current has a register assigned then    
        add current to active   
    end if  
end while
```

这里引入了一个新的集合 **inactive** 用来表示当前点落入了该 interval 的 lifetime hole 中。另外在算法中增加了 **active** 与 **inactive** 相互移动及移除部分代码。

```
TRY_ALLOCATE_FREE_REG  
set free_pos of all physical registers to max_int  
for each interval it in active do    
    set_free_pos(it, 0)  
end for  
for each interval it in inactive intersecting with current do   
    set_free_pos(it, next intersection of it with current)  
end for  
reg = register with highest free_pos  
if free_pos[reg] = 0 then   
    // allocation failed, no register available without spilling   
    return false   
else if free_pos[reg] > current.last_range.to then   
    // register available for whole current   
    assign register reg to interval current  
else   
    // register available for first part of current   
    assign register reg to interval current   
    split current at optimal position before free_pos[reg]  
end if 
```

在检查有没有空闲寄存器的时候也不能简单的判断，需要按照上面的条件，找出最合适的寄存器，如果没有找到，则要选择一个区间 Spill。

```
ALLOCATE_BLOCKED_REG  
set use_pos and block_pos of all physical 
registers to max_int  
for each non-fixed interval it in active do   
    set_use_pos(it, next usage of it after current.first_range.from)  
end for  
for each non-fixed interval it in inactive intersecting with current do   
    set_use_pos(it, next usage of it after current.first_range.from)  
end for  
for each fixed interval it in active do   
    set_block_pos(it, 0)  
end for  
for each fixed interval it in inactive intersecting with current do   
    set_block_pos(it, next intersection of it with current)  
end for  
reg = register with highest use_pos  
if use_pos[reg] < first usage of current then   
    // all active and inactive intervals are used before current, so it is best to spill current itself   
    assign spill slot to current   
    split current at optimal position before first use position that requires a register  
else if block_pos[reg] > current.last_range.to then   
    // spilling made a register free for whole current   
    assign register reg to interval current   
    split and spill intersecting active and inactive intervals for reg  
else   
    // spilling made a register free for first part of current   
    assign register reg to interval current   
    split current at optimal position before block_pos[reg]   
    split and spill intersecting active and inactive intervals for reg  
end if
```

按照上面的方法选择一个寄存器并溢出，至此，基本方法都差不多了。这里还需要补充一下，当我们将 CFG 线性化的时候，有一些细节仍然需要处理：

```
B1:
a = ...;
if (...) 
    THEN:
    a = ...;
else 
    ELSE:
    a = ...;
ENDIF:
use a
```

这里以一个简单例子说明为什么需要一步特殊的操作，假设 b1 中为 a 分配了一个寄存器，在 else 中，a 被 spill 到 stack slot 上，而 then 中仍然处于寄存器中，那么在 endif 中就出现了矛盾，a 在寄存器上还是在栈上？下面的算法用来解决这个问题。

```
RESOLVE_DATA_FLOW  
MoveResolver resolver // used for ordering and inserting moves into the LIR  
for each block from in blocks do   
    for each successor to of from do    
        // collect all resolving moves necessary between the blocks from and to    
        for each operand opr in to.live_in do     
            Interval parent_interval = intervals[opr]     
            Interval from_interval = parent_interval.child_at(from.last_op.id)     
            Interval to_interval = parent_interval.child_at(to.first_op.id)     
            if from_interval ≠ to_interval then      
                // interval was split at the edge between the blocks from and to      
                resolver.add_mapping(from_interval, to_interval)    
            end if    
        end for    
        // the moves are inserted either at the end of block from or at the beginning of block to,    
        // depending on the control flow    
        resolver.find_insert_position(from, to)    
        // insert all moves in correct order (without overwriting registers that are used later)    
        resolver.resolve_mappings()   
    end for  
end for 
```

# SSA form 线性扫描寄存器分配

SSA 形式的线性扫描的主体与上述类似， SSA 带来的优点就是能有效的降低单个 interval 的长度，这在 CISC 指令集计算机中会非常有效。同时，充分利用 SSA 形式的 IR 的稀疏特性，避免迭代式的 liveness analysis，有效的降低时间复杂度。

下面介绍基于上面算法改进的 SSA form 的寄存器分配算法：

1. 该方法使用 SSA 上活性区间分析方法建立活性区间

```
BUILDINTERVALS 
for each block b in reverse order do 
    live = union of successor.liveIn for each successor of b
for each phi function phi of successors of b do 
    live.add(phi.inputOf(b))
for each opd in live do 
    intervals[opd].addRange(b.from, b.to)
for each operation op of b in reverse order do 
    for each output operand opd of op do 
        intervals[opd].setFrom(op.id) 
        live.remove(opd) 
    for each input operand opd of op do 
        intervals[opd].addRange(b.from, op.id) 
        live.add(opd)
for each phi function phi of b do 
    live.remove(phi.output)
if b is loop header then 
    loopEnd = last block of the loop starting at b 
    for each opd in live do 
        intervals[opd].addRange(b.from, loopEnd.to)
b.liveIn = live
```

2. 按照第二种分配方法分配寄存器

3. 改进 Resolve

```
RESOLVE 
for each control flow edge from predecessor to successor do 
    for each interval it live at begin of successor do 
        if it starts at begin of successor then 
            phi = phi function defining it 
            opd = phi.inputOf(predecessor) 
            if opd is a constant then 
                moveFrom = opd 
            else 
                moveFrom = location of intervals[opd] at end of predecessor 
        else 
            moveFrom = location of it at end of predecessor 
        moveTo = location of it at begin of successor 
        if moveFrom ≠ moveTo then 
            mapping.add(moveFrom, moveTo)
    mapping.orderAndInsertMoves()
```

本质思想一样，不过针对了 SSA form 做了特有优化。

# Reference

* Linear Scan Register Allocation - MASSIMILIANO POLETTO Laboratory for Computer Science, MIT and VIVEK SARKAR IBM Thomas J. Watson Research Center
* Linear Scan Register Allocation for the Java HotSpot™ Client Compiler - Christian Wimmer
* Linear Scan Register Allocation on SSA Form - Christian Wimmer Michael Franz
* [寄存器分配问题？- 知乎](https://www.zhihu.com/question/29355187)