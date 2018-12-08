---
title: 'Effective C++: Accustoming Yourself to C++'
date: 2017-03-02 12:40:11
tags: C++
categories: C++

---

# View C++ as a federation of languages

今天的C++已经是一个多重泛型编程语言，它同时支持：

- 过程式
- 面对对象
- 函数形式
- 泛型形式
- 元编程形式

而我们在使用C++时，应当针对性的使用。C++的高效编程守则视情况而变化，取决于你使用他的那一部分。

<!-- more -->

# Perfer consts, enums, and inlines to #defines

在C++中，不建议使用 #define 来定义常量或者函数，应该使用语言自身机制，将预处理器的工作交给编译器来做。

使用 const 和 enum 可以让标识符进入符号表，报错的时候就不会出现“魔数”。而 inline 则替代宏函数，在保证函数行为一致性的同时，确保类型安全。

```
template<typename T>
inline bool call(const T &a, const T &b) {
    return (a > b) ? a : b;
}
```

# Use const whenever possible

const 允许你指定一个 **语义约束** ，而编译器会强制执行这项约束。const 可以被施加于任何作用域内的对象、函数参数、函数返回类型、成员函数本体。

当 const 与指针同时出现的时候往往具有迷惑性，实际上并不高深莫测。如果 const 出现在 \* 左边，表示被指物是常量；如果出现在右边，则表示指针本身是常量。

在使用 STL 的时候需要注意使用 const_iterator 而不是 const iterator 。因为 iterator 是模拟指针，在编译器的视角里于普通变量无异。

将 const 运用于成员函数的目的，是为了确认该成员函数可以作用于 const 对象。如果一个对象被定义为了 const，那么编译器会对它进行 **bitwise constness** 约束，即成员函数只有在不更改对象之任何成员变量（static 除外）时才可以说是 const。不过实际上项目中可能出现特殊情况，比如多线程中保证互斥的对象必须能改变，这就是 **logic constness** 。对于这种情况，可以使用 mutable 释放掉 non-static 成员变量的 **bitwise** 约束。

> 编译器强制实施 **bitwise constness**，但是你编写程序的时候应使用“概念上的常量”（conceptual constness）。

当 const 和 non-const 成员函数有着实质性的等价实现时，令 non-const 版本调用 const 版本可以避免代码重复。

# Make sure that objects are initialized before they're used

C++ 并没有保证所有的变量都能被初始化，而读取未初始化的值会导致不明确行为。所以要在使用对象之前将其进行初始化。对于没有任何成员的内置类型，需要手动完成初始化。对于内置类型外的，则由构造函数进行初始化，所以确保每一个构造函数都将对象的每一个成员初始化。

C++ 规定了对象成员变量的初始化动作发生在进入构造函数本体之前。最好的方式是总使用成员初值列表完成初始化。初值列表列出的成员变量，其排列次序应该和他们在class中的声明次序相同。

对于定义于不同编译单元内的 non-local static 对象初始化顺序，C++没有明确定义。而解决办法则是 Singleton 模式解决，因为 C++ 保证了函数内的 local static 会在“该函数被调用期间”“首次遇上该对象的定义式”时被初始化。
