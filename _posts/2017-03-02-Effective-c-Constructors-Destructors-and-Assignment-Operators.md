---
layout: post
title: 'Effective c++:Constructors,Destructors,and Assignment Operators'
date: 2017-03-02 17:05:47
tags: C++
categories: C++

---

C++ 中有三个特殊的函数，构造、析构、赋值。

<!-- more -->

# Know what functions C++ silently writes and calls

在 C++ 中，如果你没有事先没有声明，那么编译器会为它声明一个构造函数，一个 copy 构造函数，一个 copy assignment 操作符和一个析构函数。这些函数都是属于 public inline，且只有用户有调用的时候才会被创建。其中需要注意的有以下几点：

- 析构函数默认为 non-virtual 
- copy 类默认拷贝每一个 non-static 函数的值
- 一旦定义了构造函数，则不会创建默认构造函数
- 有 reference 或 const 时不产生默认 operator=

# Explicitly disallow the use of compiler-generated functions you do not want

有的时候我们不需要编译器产生的赋值或者其他默认函数，那我们可以将其声明为私有且不实现。不过这种办法并不完美，friend 是可以访问 private 的；另外有人不小心将其实现了也会违背预期。一种更好的办法是将其封装：

```
class noncopyable {
    noncopyable(const &nocopyable);
    nocopyable &operator(const noncopyable &) const;
public:
    noncopyable() {}
    ~noncopyable() {}
};

class Bar : noncopyable {}
```

总之，为驳回编译器自动提供的机制，可以将成员函数声明为 private 并且不予以实现；或者使用 noncopyable 这样的基类进行限制。

# virtual function & constructors and destructors

C++ 的虚函数可以提供动态绑定，不过在构造函数和析构函数中要避免使用到虚函数（哪怕是间接调用也不可以）。在构造完成之前和析构调用之后，对象都不再是一个完整的对象。这也不难理解，因为子类于父类前析构，那么此时父类调用的虚函数已经不再动态绑定到子类，则没有达到预期目的。

而对于任何具有多态性质的基类都应该将其析构函数声明为 virtual，否则会出现无法完全回收对象的问题。

```
class base {
public:
    ~base() {}
};

class child : public base {
    // ...
};

base *b = new child();
delete b;   // Error: boom
```

# Handle assignment to self in operator =

对于自我赋值，一般的做法是进行证同测试，另外采用精心安排的语句导出异常安全的代码。一种比较好的办法则是使用 copy and swap 技术：

```
Class &operator=(const Class &c) {
    Class s(c);
    swap(s);
    return *this;
}
```

这中办法将目标拷贝到一个临时变量中，然后和当前对象进行交换。如果构造变量失败时，不会影响原有的数据；并且保证了swap为异常安全，那么整个函数就能保证异常安全。最后，类似于 scope_ptr ，临时变量在退出时析构并释放资源。
