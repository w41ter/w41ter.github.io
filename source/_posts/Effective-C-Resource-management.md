---
title: 'Effective C++:Resource management'
date: 2017-03-05 13:31:06
tags: C++
categories: C++
---

C++ 中不同于Java之类的语言，编写者需要对资源进行手动管理。

<!-- more -->

# Use object to manage resources

和C语言一样，C++中也需要对手动申请的内存进行释放。

```
void bar() {
    int *p = new int;
    //...
    delete p;
}
```

如果总是依赖于手动调用 delete 释放资源是行不通的。手动管理资源总会出现差错，比如后面修改代码时加上了一句 return ，那么申请的内存将得不到释放。另外，在一下非常复杂的系统中，可能出现资源被多个模块公有，如果简单释放，可能导致其他部分崩溃。

现在需要的是一种自动进行内存管理的机制：把资源放到对象内，依靠C++提供的“析构函数自动调用机制”确保资源的释放。这种机制有两个关键的想法：

- 获取资源后立刻放进管理对象内
- 管理对象运用析构函数确保资源被正确释放

实际上“以对象管理资源”的观念通常被称为“资源获取时机便是初始化时机（Resource Acquisition Is Initialization; RAII）。C++中提供了基础的 RAII 类，分别是:

- std::shared\_ptr 及 std::weak\_ptr
- std::unique\_ptr

我们改写一下例子：

```
void bar() {
    std::shared_ptr<int> wrapper(new int);
    //...
}
```

当然资源不仅仅是内存，也可以是文件描述符、互斥锁等。C++ 的 RAII 类中允许我们定义自己的删除函数，所以可以直接使用之管理其他非内存资源。

# Think carefully about copying behavior in resource-managing classes

资源因为其特殊性，所以不能简单拷贝。通常用于处理拷贝的方式有以下两种：

- 禁止复制
- 对底层资源进行“引用计数”

`unique_ptr` 要求对象同一时刻只能拥有一个 owner，而 `shared_ptr` 则使用引用计数实现；对 `unique_ptr` 只能进行所有权转移，`shared_ptr` 则要避免循环计数。

# Use the same form in corresponding uses of new and delete

如果你在 `new` 表达式中使用了[]，那么也应该在 `delete` 中使用[]。当然 C++ 中提供了 `vector` 和 `string` 等 templates，可以将对数组的要求降为 0。如果你非要使用原生数组，也可以使用 `unique_ptr` 管理，只需要在类型模板参数后添加[]：

```
unique_ptr<int[]> arrays(new int[10]);
```

然而 `shared_ptr` 并不支持，如果你非要使用，那么请自己定义 `delete`。

# store newed objects in smart pointers in standalone statements

C++ 在实现上有很大的弹性，所以编译器可能会对指令进行重排，所以凡是写标准未定义执行顺序的代码，都可能出现问题。例如 C++ 没有规定参数求值，那么求值结果跟顺序有关时，就会出现非预期行为。

如果其中涉及到资源管理，那么可能造成资源泄露，所以 C++ 提供了单独的环境将对象置于资源管理对象中：

```
int foo() {
    //...
    throw ...;
    //...
}

void bar(std::shared_ptr<int> ptr, int);

bar(std::shared_ptr<int>(new int), foo());  // dangerous

// 上面的代码求值顺序未定义，通过编译器重排后可能导致内存泄露

bar(std::make_shared<int>(), foo());
```

单独的环境中确保资源能够正确放入资源管理对象，从而保证了不会发生资源泄露。

