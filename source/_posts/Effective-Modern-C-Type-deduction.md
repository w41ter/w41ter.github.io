---
title: Effective Modern C++ - Type deduction
date: 2017-03-12 21:54:36
tags: C++
categories: C++

---

<!-- more -->

# 模板类型推导

```
template<class Type>
void f(ParamType p);
```

如上述代码，对于模板有两种类型需要推导。而具体推导细节有三种方案：

1. ParamType 为引用，但非 `universal reference`；
2. ParamType 为 `universal reference`；
3. ParamType 非引用

## 一

对于第一种情况，推导方式如下：

1. 参数如果为引用，那么忽略；
2. 剩下部分与 ParamType 做匹配得出 Type 类型

## 二

第二种情况涉及到引用折叠。

1. 如果参数为左值引用，那么 Type 和 ParamType 类型为左值引用；
2. 如果参数为右值引用，那么应用方案一的情况

## 三

这种情况下，参数默认以 “pass by value” 的方式传递：

1. 如果参数为引用，忽略引用部分；
2. 忽略后以值拷贝规则匹配 Type 类型；

# auto

auto 类型推导和模板类型推导的唯一区别是关于处理 `braced initializer` 的区别：

> auto 认为 braced initializer 表示为 `std::initialzier` 列表

同时，在 C++ 14 中，auto 还可以用于推导返回值类型，此时规则等同于模板类型推导。

# decltype

不同于 auto，decltype 返回表达式的具体类型。decltype 的更多用于推导与参数类型相关的返回类型：

```
auto f(int a) -> decltype(a) {}
```

因为 C++ 14 中可以使用 auto 推导返回值类型，而 auto 推导规则限定不太灵活。此时提供了 `decltype(auto)` 来完美推导返回值类型（`decltype(auto)` 也可以用于定义变量）。

C++ 中规定 (x) 返回的是左值引用，所以 `decltype(x)` 和 `decltype((x))` 是不同的类型。