---
title: Traditional SSA Construction Algorithm
date: 2016-08-17 08:21:38
tags: Compile
categories: 编译器实现
---

由于 SSA (static single assignment form) 能够使得程序分析变得更方便快捷，已经被许多编译器用于 IR (intermediate representations)。

<!-- more -->

## SSA是什么？
SSA 即静态单赋值，之所以称之为单赋值，是因为每个名字在SSA中仅被赋值一次。

## 传统编译器流程

在传统的编译器中，parse 过后通常生成 AST，并将 AST 转换为线性 IR, 并在这个基础上构造 SSA，然后进行寄存器分配生成目标代码等。

## 线性 IR 到 SSA 构造具体步骤

这里介绍本文剩下部分的内容--构造 SSA from。

1. 遍历 IR 构造 CFG
2. 计算支配边界
3. 确定 Phi 函数位置
4. 变量重命名

## 遍历 IR 构造 CFG

CFG 由基本块组成，所以首先确定基本块：

> 基本块算法：
> a) 找基本块入口源代码的首行或者转移代码（有条件和无条件）或者转移代码的下一行
> b) 基本块构造：通过入口点开始，将其组成各自的基本块。基本块语句序列的特征：从不包含它本身的进入点到其他进入点或者到某条转移语句或者到某条停止语句
> c) 如果有语句不在任一基本块中，那么它为 ”死代码“，删除

当确定基本块后，紧接着构造 CFG:

> 控制流图构造如果在一个有序代码中，基本块 B2 跟在 B1 后，那么产生一个由 B1 到 B2 的有向边。
> a) 有跳转点。这个点从 B1 的结束点跳到 B2 的开始点
> b) 无跳转点（有序代码中），B2 跟在 B1 后，且 B1 的结束点不是无条件跳转语句 

## 计算支配边界

放置 Phi 函数的关键在于了解在每个汇合点处究竟哪个变量需要 Phi 函数。在进一步讲解之前，需要引入支配的概念。

### 支配集合

假设对于任意 CFG 图，Bi 表示第 i 个基本块，那么对于任意的 Dom(Bi) 表示从 CFG 入口开始遍历，到达 Bi 基本块中每条路径都包含的公共基本块。计算算法如下

```
Dom(0) = { 0 }
for i in range(1, n):
    Dom(i) = N

changed = true
while changed:
    changed = false
    for i in range(1, n):
        for preds j in i:
            temp = temp ∩ Dom(j)
        temp = { i } ∪ temp

        if temp != Dom(i):
            Dom(i) = temp
            changed = true
```

### 支配者树

而对于基本块 Bi 中的定义，当值到达某个节点 m 时，仅在满足下述两个条件的汇合点才需要插入对应的 Phi 函数：

1. Bi 支配 Bm 的一个前驱
2. Bi 并不严格支配 Bm 

这里把相对于 Bi 具有这种性质的结点 Bm 的集合称为 Bi 的支配边界，记作 DF(n)。

而 Bi 严格支配的结点 Dom(Bi)-Bi , 则该集合中与 Bi 最接近的结点称为 Bi 的直接支配结点，记作 IDom(Bi)。

### 支配边界

下面的算法用于计算流图支配边界：

```
for block in CFG:
    DF(n) = {}
for block in CFG:
    if block.predecessors.size() > 1:
        for p in block.predecessors:
            runner = p
            while runner != IDom(block):
                DF(runner) = DF(runner) ∪ { n }
                runner = IDom(runner)
```

## 确定 Phi 函数位置

有了支配边界之后，编译器就可以更精确地判断何处可能需要 Phi 函数。其基本思想很简单，在基本块 Bi 中对 x 定义，则要求在 DF(b) 集合包含的每个结点起始处都放置一个对应的 Phi 函数。只在单个基本块中活动的变量，绝对不会出现与之相应的活动 Phi 函数。所以可以计算跨多个程序块的活动变量名的集合，该集合被称为全局名字结合。它可以对该集合中的名字插入 Phi 函数，而忽略不在该集合中的名字。下面的算法用于计算全局名字集合：

```
Globals = {}
Initialize all the blocks sets to {}

for each block b in CFG:
    VarKill = {}
    for each operation i in b in order
        assume that opi is "x = y op z"
        if y not belong VarKill:
            Globals = Globals ∪ { y }
        if z not belong VarKill:
            Globals = Globals ∪ { z }
        VarKill = VarKill ∪ { x }
        blocks(x) = blocks(x) ∪ { b }
```

下面的算法用于重写代码：

```
for each name x in Globals:
    WorkList = blocks(x)
    for each block b in WorkList:
        if d has no phi-function for x:
            insert a phi-function for x in d 
            WorkList = WorkList ∪ { d }
```

## 变量重命名

在最终的静态单赋值形式中，每个全局名字都变为一个基本名，而对该基本名的各个定义则通过添加数字下标来区分，该算法如下：

```
for each global name i:
    counter[i] = 0
    stack[i] = 0
Rename(block0)

NewName(n):
    i = counter[n]
    counter[n] = counter[n] + 1
    push i onto stack[n]
    return "ni"

Rename(b):
    for each phi-function in b "x = phi(...)":
        rewrite x as NewName(x)
    
    for each operation "x = y op z" in b:
        rewrite y with subscript top(stack[y])
        rewrite z with subscript top(stack[z])
        rewrite x as NewName(x)
    
    for each successor of b in the CFG:
        fill in phi-function parameters

    for each successor s of b in the dominator tree:
        Rename(s)

    for each operation "x = y op z" in b 
        and each phi-function "x = phi(...)":
        pop(stack[x])
```

## Phi function Elimination

消除 Phi 函数主要有两步操作。首先编译器可以保持 SSA 名字空间原样不动，将每个 Phi 函数替换为一组复制操作并放入前驱中。比如对于 x = phi(i, j), 编译器应该在传入 i 的基本块末尾加上 x = i, 在传入 j 的基本块末尾加上 x = j：

```
B1:
    x.1 = a
    goto B3:
B2:
    x.2 = b
    goto B3:
B3:
    x.3 = phi(x.1, x.2)
    c = x.3
转换后

B1:
    x.1 = a
    x.3 = x.1
    goto B3
B2:
    x.2 = b
    x.3 = x.2
B3:
    c = x.3
```

当当前基本块 B1 某一个前驱结点 B2 有多个后继结点时 (B2, B1)，无法应用上述方法，因为添加的复制操作不仅会流入当前基本块，也会流入其他后继结点。为了弥补这种问题，编译器可以拆分 (B2, B1) 在中间插入一个新的基本块，将所有复制操作放入新的基本块中。这里 (B2, B1) 这样的边称为关键边。

在转换过程中出现的大部分问题都可以通过这种变换解决，但还有两个更为微妙的问题：1、丢失复制，是因为激进的程序变换与不可拆分的关键边共同引起的；2、交换，是因为某些激进的程序变换与静态单赋值形式的详细定义之间的交互所致。这里不做介绍，有兴趣可以参考 reference。

## 参考 

[1] Efficiently Computing Static Single Assignment Form and the Control Dependence Graph RON CYTRON, JEANNE FERRANTE, BARRY K. ROSEN, and MARK N. WEGMAN IBM Research Division and F. KENNETH ZADECK Brown University

[2] Engineering a Compiler, Second

[3] [llvm的reg2mem pass做了哪些事情？](https://www.zhihu.com/question/49642237#)

[4] [Phi node 是如何实现它的功能的？](https://www.zhihu.com/question/24992774)