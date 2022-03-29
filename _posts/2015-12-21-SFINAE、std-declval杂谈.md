---
layout: post
title: 'SFINAE、std::declval杂谈'
date: 2015-12-21 21:16:32
tags: C++
---

## 前言

在[知行一](http://purecpp.org/)社区上看到一篇文章介绍设计 UnitTest 的文章。在看其源代码时，发现有处代码并不是很懂。通过查找相关资料，解决了该问题，记录在此。

<!-- more -->

## 问题

作者在谈到其设计目标时，提供了一些用例，其中：

```
TEST_REQUIRE(condition, "这样", "可以", "打印", "很多"， "行"); 
TEST_CHECK(condigion, []{ /** 这里可以做些事 */ });
TEST_REQUIRE(condition, logger, args_to_logger);    /**< logger can be any callable object */
```

这样的用法让我或多或少有些疑惑。于是看了其实现，其中关键问题部分代码如下：

```
template <typename F, typename... Args, typename = decltype(std::declval<F>()(std::declval<Args>()...))>
void do_check_failed(F&& f, Args&&... args)
{
    f(std::forward<Args>(args)...);    
}

template <typename... Msgs>
void do_check_failed(Msgs&&... msgs)
{
    std::initializer_list<int>{(std::cout << msgs << std::endl, 0)...};
}
```

这两个函数实现了传递多种参数的方式。其中令我疑惑的部分在于`typename = decltype(std::declval<F>()(std::declval<Args>()...))`部分的实现。现在让我一步一步展开。

## declval

declval主要用于配合decltype在模板形参构造函数不明确的情况下（也就是不需要通过构造函数构造变量）来使用模板形参的成员。在进一步探索前，先看一下declval的定义：

```
template<class T>
typename add_rvalue_reference<T>::type declval() noexcept;  // as unevaluated operand
```

该函数并没有完整定义，所以只能在未发生函数调用(unevaluated)的上下文环境中使用。这正好就是用于配合decltype(decltype不求值)。假设有这么一个场景，你需要得到某类型中某函数返回值的类型，然而该函数并没有构造函数:

```
struct Default {
    Default(const Default &d) {}
    int foo() const { return 1; }
};

int main() {
    decltype(Default.foo()) n1 = 1;
    return 0;
}
```

这样的代码无法通过编译。如果加上declval：

```
int main() {
    decltype(std::declval<Default>().foo()) n1 = 1;
    return 0;
}
```

这样就能顺利通过编译。当然，更多的使用场景是出现在模板的使用中。

## SFINAE

SFINAE(Subsitiution Failure Is Not an Error!)可以理解为匹配失败不是错误，更严格的说是参数匹配失败不是一个编译时错误。考虑下面的应用场景，我们定义一个模板函数`add`，它只为数值类型提供服务：

``` 
template<typename T>
T add(T &t1, T &t2) {
    if (T is arithmetic) 
        return t1 + t2;
    else 
        // error
}
```

C++并没有提供反射机制，想实现这样的操作需要开动我们的脑筋。让我们看一下下面的代码：

```
template<typename T, bool B> struct enable_if_;
template<typename T> struct is_arithmetic_;

template<typename T, bool B>
struct enable_if_ {
    typedef T type;
};

template<typename T>
struct enable_if_<T, false> {};

template<typename T>
struct is_arithmetic_ { 
    enum { value = false }; 
};

template<>
struct is_arithmetic_<int> { 
    enum { value = true }; 
};

template<typename T>
typename enable_if_<T, is_arithmetic_<T>::value>::type add(T &t1, T &t2) {
    return t1 + t2;
}

int main() {
    int a = 1, b = 2;
    cout << "add(a, b) = " << add(a, b) << endl;
    // add("string", "string"); error: no matching function for call to 'add(const char [7], const char [7])'
    return 0;
}

```

在实现`add`函数时，通过`is_arithmetic_`判断是否可以计算，如果可以，则允许该次类型推导，否则拒绝并报错。`enable_if_`和`is_arithmetic_`的实现都使用了模板特例化，对于`is_arithmetic`，我们认为的将所有可以计算的实例化，将`value`的值改为`true`（这里仅作演示，只对int进行实例化）。对于`enable_if_`，能够成功推导的，则保存其原始类型，否则不保存。这样，对于`add("string", "string");`在编译时，编译器通过推导出`is_arithmetic_::value == false`，那么就选择特例化版本，而特例化版本的`enable_if_`中并没有`type`类型，所以该次推导失败。而`add(a, b);`部分正好相反，成功推导。

## 原始问题

现在回到最初的问题当中，当定义一个模板参数时，可以为之匿名：

```
template<typename T, typename = void>
void foo(...) {}
```

这样，对于`typename = decltype(std::declval<F>()(std::declval<Args>()...))`的作用就非常清楚了。如果传入参数为函数，那么就会选择该实例，否则选择另一实例。如果不太明白还可以看看下面的例子：

```
//
// 让*.equal_range支持range-based循环
//
#include <iostream>
#include <map>

namespace std
{
    template<typename Iter, typename = typename iterator_traits<Iter>::iterator_category>
    Iter begin(pair<Iter, Iter> const &p)
    {
        return p.first;
    }
    template<typename Iter, typename = typename iterator_traits<Iter>::iterator_category>
    Iter end(pair<Iter, Iter> const &p)
    {
        return p.second;
    }
}

int main()
{
    std::multimap<int, int> mm { {1, 1}, {1, 2}, {2, 1}, {2, 2} };
    for(auto &v : mm.equal_range(1)) {
        std::cout << v.first << " -> " << v.second << std::endl;
    }
}
```

该代码摘抄自stackoverflow。