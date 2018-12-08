---
title: Simple and Direction SSA Constriruction Algorithm
date: 2016-08-18 08:04:58
tags: Compile
categories: 编译器实现
---

前面讲到了传统的 SSA 构造方式，直接从线性 IR 构造 SSA。而本文将介绍另外的方法允许从 AST、Bytecode 甚至源代码直接构造 SSA 形式。

<!-- more -->

## LLVM 中的方法

LLVM ir 为 SSA 形式，如果用户手工翻译 AST，那么只有在翻译的时候直接生成 SSA 形式中间代码。不过 LLVM 给用户留下了一个后门，可以将变量全部表达成为 Memory 形式，通过指针操作。然后通过 Mem2Reg pass 转换成 SSA 形式。

这里不介绍翻译时候的方式，仅仅介绍一下 Mem2Reg pass。下面的代码抄自 LLVM 中：

```
// 遍历指令序列找到 alloca
for (Instruction instr : instructions)
{
    if (isa<Alloca>(instr))
        allocas.push_back(instr);
}

// 一个一个的提升 alloca 指令
for (Alloca alloca : allocas)
{
    // 判断是否可以提升
    if (!alloca.isAllocaPromoteable())
        continue;
    
    // 跳过无使用者的alloca指令
    if (alloca.user_begin() == alloca.user_end())
        continue;
        
    // 收集alloca指令的使用，定义信息
    info.analyzeAlloca(alloca);
         
    // 下面的函数，对只有一次定义（即只有一条 store 指令）的 alloca 进行优化
    // 把所有的 load 指令全部用定义时保存的 value 替换
    if (info.definingBlocks.size() == 1)
        rewriteSingleStoreAlloca(alloca, info);
    
    // 下面的代码仅仅对只在一个基本块中使用和定义的alloca指令进行优化
    if (info.onlyUsedOneBlock)
        promoteSingleBlockAlloca(alloca, info);

    // 插入无参数的Phi函数，使用标准的基于支配边界的算法，其中使用DJ图的方式进行了优化
    determineInsertionPoint(alloca, allocaNum, info);

    // 使用 IDF 和标准 ssa 构造算法提升 alloca ，决定那些需要插入 Phi 函数
    DefBlocks.insert(Info.DefiningBlocks.begin(), Info.DefiningBlocks.end());
    ComputeLiveInBlocks(AI, Info, DefBlocks, LiveInBlocks);
    IDF.setLiveInBlocks(LiveInBlocks);
    IDF.setDefiningBlocks(DefBlocks);
    IDF.calculate(PHIBlocks);

    // 执行 SSA 重命名算法，并插入 Phi 节点
    RenamePassWorkList.emplace_back(&F.front(), nullptr, std::move(Values));
    do {
        // RenamePass may add new worklist entries.
        RenamePass(RPD.BB, RPD.Pred, RPD.Values, RenamePassWorkList);
    } while (!RenamePassWorkList.empty());

    // 移除 allocas
    for (unsigned i = 0, e = Allocas.size(); i != e; ++i) 
    {
        Instruction *A = Allocas[i];
        A->replaceAllUsesWith(UndefValue::get(A->getType()));
        A->eraseFromParent();
    }

  // 最后执行一趟消除平凡Phi函数的操作，
    while (eliminatedAPHI)
    {
        // if the phi merges one value and/or undefs, get the value
        if ((V = simplifyInstruction(phi, DT)) != null)
        {
            phi.replaceAllUsesWith(V);
            phi.eraseFromBasicBlock();
            newPhiNodes.remove(entity);
            eliminatedAPHI = true;
            continue;
        }
    }
}
```

## 直接构造

这种方法来源于论文：

> Simple and Eﬃcient Construction of Static Single Assignment Form
Matthias Braun1, Sebastian Buchwald1, Sebastian Hack2, Roland Leißa2, Christoph Mallon2, and Andreas Zwinkau1

下面介绍该构造方法。

### Local Value Numbering

这部分操作以基本块为单位，所以生成的 IR 必须为 CFG 形式。CFG 形式能够非常容易的从源代码构造，这里略过。

该方法按照程序执行的顺序处理所有的表达式，并且在变量和其定义表达式之间建立映射。也就是说当遇到对变量赋值时，把赋值符号右边的表达式最为当前变量的定义。当一个变量被访问的时候，我们就查找其定义。上述的过程就叫做 **local value numbering**。

如果一个基本块中完成了 **local value numbering**，这个基本块就被称为 **filled**。 只有一个基本块完成了 **local value numbering** 后，才能够添加后继基本块。这个属性会在处理 **incomplete CFGs** 的时候使用。


Algorithm 1: Implementation of local value numbering

```
writeVariable(variable, block, value): 
    currentDef[variable][block] ← value 
    
readVariable(variable, block): 
    if currentDef[variable] contains block: 
        # local value numbering
        return currentDef[variable][block] 
    # global value numbering 
    return readVariableRecursive(variable, block) 
```

### Global Value Numbering

正如上面算法展示，当读取变量定义的时候，如果当前基本块没有变量的定义，那么只能递归地查找其前驱基本块。递归地查找算法如下：

如果基本块只有一个前驱，仅仅在其前驱中查找定义，否则，构造一个 φ 函数，将其所有前驱中定义加入该 φ 函数，并将该 φ 函数作为该基本块的定义。

需要注意的是该查找方式可能导致循环查找，比如在循环体中查找定义。为了避免程序死循环，在查找前先为该基本块建立一个没有任何操作数的 φ 函数作为其定义。

Algorithm 2: Implementation of global value numbering

```
readVariableRecursive(variable, block): 
    if block not in sealedBlocks: 
        # Incomplete CFG 
        val ← new Phi(block) 
        incompletePhis[block][variable] ← val
    else if |block.preds| = 1:
        # Optimize the common case of one predecessor: No phi needed 
        val ← readVariable(variable, block.preds[0])
    else : 
        # Break potential cycles with operandless phi 
        val ← new Phi(block) 
        writeVariable(variable, block, val) 
        val ← addPhiOperands(variable, val) 
    writeVariable(variable, block, val) 
    return val

addPhiOperands(variable, phi): 
    # Determine operands from predecessors 
    for pred in phi.block.preds: 
        phi.appendOperand(readVariable(variable, pred)) 
    return tryRemoveTrivialPhi(phi) 
```

这种查找方式可能导致多余的 φ 函数，称为 **trivial** 。如果一个 φ 函数引用了自身和另一个定义，那么就叫做 **trivial** φ 函数。比如有 `a.1 = φ<a.1, a.0>`。这个 φ 函数完全可以被另一个定义给替换。还有一种特殊的情况，φ 函数仅仅引用了自身，这种情况仅仅发生在不可达或者开始基本块，这时用一个 `Undef` 值代替。

需要注意的是如果我们替换了 `trivial` φ 函数，可能导致引用该 φ 函数的值也变成 `trivial` φ 函数，所以还需要递归地进行替换操作。

Algorithm 3: Detect and recursively remove a trivial φ function 

```
tryRemoveTrivialPhi(phi): 
    same ← None for op in phi.operands: 
        if op = same || op = phi: 
            # Unique value or self−reference
            continue 
        if same = None: 
            # The phi merges at least two values: not trivial 
            return phi 
        same ← op
        if same = None: 
            # The phi is unreachable or in the start block
            same ← new Undef() 

        # Remember all users except the phi itself
        users ← phi.users.remove(phi) 
        # Reroute all uses of phi to same and remove phi
        phi .replaceBy(same)

        # Try to recursively remove all phi users, 
        # which might have become trivial 
        for use in users: 
            if use is a Phi: 
                tryRemoveTrivialPhi(use) 
        return same 
```

上述操作目前还无法处理未完成的循环，比方说如果循环体未处理完，那么循环头部分仍然有可能加入新的前驱，这就是前面引用到的 `Incomplete CFGs`。

### Handling Incomplete CFGs 

如果一个基本块不会再加入任何前驱结点，那么就可以称为 `sealed` 基本块。因为只有 `filled` 基本块拥有后继，所以前驱基本块必须是 `filled`。

`filled` 基本块可以为其后继提供变量定义，而 `sealed` 基本块可能会从其前驱中查找变量定义。

Algorithm 4: Handling incomplete CFGs

```
sealBlock(block): 
    for variable in incompletePhis[block]: 
        addPhiOperands(variable, incompletePhis[block][variable]) 
        sealedBlocks.add(block) 
```

如果在一个属于 `filled` 且非 `sealed` 基本块中查找变量定义呢？如前面算法2提到的，对于非 `sealed` 基本块，建立一个 函数并保存在 `incompletePhis` 中为其后继提供定义。当该非 `sealed` 基本块不会有新的前驱加入时，对其进行 `seal` 操作。

`seal` 操作会对该基本块的所有 `incompletePhis` 进行处理，完成处理后将该基本块加入 `sealed` 集合。

### 结束

通过上述四个算法，能够完成 SSA 形式构造，当然，还有进一步的优化这里就不讲了，有兴趣可以直接看论文。

