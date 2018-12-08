title: Y组合子(Y combinator)与匿名Lambda
date: 2016-02-29 16:35:12
tags: Compile
categories: 编译器实现
---

## Y组合子(Y combinator)与匿名 Lambda

Y组合子是函数编程的理论基础，lambda 演算的一部分。它的作用就是把匿名 lambda 函数自身给计算出来。

<!-- more -->

在介绍组合子之前需要先介绍不动点：不动点（fixed point）是指函数的某种输入和函数本身相等，也就是 f(x) 等于 x 。当然，继续之前你还得了解 first class function 中的高阶函数和柯里化(currying)的概念。

现在，尝试使用前面设计的语言来做一个例子解释 Y 组合子的用途，该语言中名字只有在定义完成后才可见，也就是定义函数时无法知道自己的名字，这样就导致了无法进行递归。那么如何在这门语言中使用递归呢？

所谓 Y 组合子即一个 Y 函数，它用于计算高阶函数的不动点。假设有函数 f(x) 和高阶函数 g(x)，我们用 t 来表示 g(x) 的不动点。那么就有 `g(Y(g)) = Y(g)` 等价于 `g(t) = t`，其中 Y(g) 得到的是 g(x) 的不动点。

下面，我们来计算 Y 的形式，定义斐波拉契函数如下：

```
define f = function(fib) {
  return function(n) {
    if (n <= 2) return 1;
    return fib(n-1) + fib(n-2);
  };
};
```

现在，只需要将 `fib` 函数传递给 `f` 就能得到 `fib`...显然这种办法是行不通的。我们进行如下改写：

``` 
define fib = function(h, x) {
  if (x <= 2) return 1;
  return h(h, x-1) + h(h, x-2);
};
fib(fib, 10);
```

虽然实现了递归，但是这种办法没有那么优美。我希望能够像其他语言一样，使用 `fib(10)` 进行调用。现在将函数柯里化:

```
define fib = function(h) {
  return function(x) {
    if (x <= 2) return 1;
    return h(h)(x-1) + h(h)(x-2);
  };
};
fib(fib)(10);
```

这样的方式仍然不够好，我们进一步将内部的 `h(h)` 部分改为 `fib(x)`：

```
define fib = function(h) {
  return function(x) {
    let f = function(fib) {
      if (x <= 2) return 1;
      return fib(x-1) + fib(x-2);
    };
    return f(h(h));
  };
};
fib(fib)(10);
```

现在发现其中的 `f` 定义的部分与最开始的代码相似，改写如下：

```
define fib = function(h) {
  return function(x) {
    let f = function(fib) {
      return function(n) {
        if (n <= 2) return 1;
        return fib(n-1) + fib(n-2);
      };
    };
    return f(h(h))(x);
  };
};
fib(fib)(10);
```

然后将 `f` 部分提取出来：

```
define f = function(fib) {
  return function(n) {
    if (n <= 2) return 1;
    return fib(n-1) + fib(n-2);
  };
};

define fib = function(h) {
  return function(x) {
    return f(h(h))(x);
  };
};
fib(fib)(10);
```

这里发现，利用柯里化，就能得到 Y 组合子，现在对其进行包装：

```
define f = function(fib) {
  return function(n) {
    if (n <= 2) return 1;
    return fib(n-1) + fib(n-2);
  };
};

define Y = function(f) {
  let warp = function(h) {
    return function(x) {
      return f(h(h))(x);
    };
  };
  return warp(warp);
};

define fib = Y(f);
fib(10);
```

现在回头看 Y 组合子的定义，Y(f) 就得到了 f 的不动点。那么现在就可以很友好的得到 `fib` 函数：

```
define Y = function(f) {
  let warp = function(h) {
    return function(x) {
      return f(h(h))(x);
    };
  };
  return warp(warp);
};

define fib = Y(function(fib) {
  return function(n) {
    if (n <= 2) return 1;
    return fib(n-1) + fib(n-2);
  };
});
fib(10);
```

现在，当然这样的 Y 函数依然有限制，不过已经实现了预期的需求：匿名递归 lambda。

