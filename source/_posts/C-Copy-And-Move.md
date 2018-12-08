title: 'C++0x:Copy And Move'
date: 2016-01-07 12:53:51
tags: C++
categories: C++
---

C++ 提供了5种特殊的成员函数来控制对象的拷贝、移动、赋值和销毁，统称为*拷贝控制操作(copy control)*。这几个函数分别是*拷贝构造函数(copy constructor)*、*拷贝赋值运算符(copy assignment operator)*、*移动构造函数(move constructor)*、*移动复制运算符(move assignment operator)*和*析构函数(destructor)*。

<!-- more -->

## 拷贝构造函数

如果一个构造函数的第一个参数是自身类型的引用，且任何额外的参数都有默认值，则此函数是*拷贝构造函数*。

```
class test {
public:
  test(const test&);  // copy constructor
};
```

如果我们没有为一个类定义*拷贝构造函数*，编译器会为我们定义一个*合成拷贝构造函数(synthesized copy constructor)*。对于*合成拷贝构造函数*，在发生拷贝时，每个成员的类型会决定其拷贝方式，类成员使用其拷贝构造函数，内置类型成员直接拷贝，数组会逐个元素地拷贝。

## 拷贝构造时机

对于没有进行函数调用的初始化，如果使用等号(=)初始化一个变量，则实际上执行的是*拷贝初始化(copy initialization)*，如果不使用等号，则执行*直接初始化(direct initialization)*。

```
string s1("direct initialization");
string s2(s1);    // direct initialization
string s3 = "copy initialization"; 
string s4 = s2;   // copy initialization
```

如果初始化中涉及到函数调用，那么在下列情况也会发生*拷贝初始化*：

- 将一个对象作为实参传递给一个非引用类型的形参
- 从一个返回值类型为非引用类型的函数返回一个对象
- 花括号列表初始化一个数组中的元素或者一个聚合类中的成员

> 如果一个类满足下列条件，则称为聚合类：
>
> - 所有成员都是 `public`的
> - 没有定义任何构造函数
> - 没有类内初始值
> - 没有基类，也没有 `virtual` 函数
>
> 对于聚合类，可以使用花括号括起来的成员初始值列表进行初始化：
>
> ```
> struct data {
>   int ival;
>   string s;
> };
> data val = { 1, "string" };
> ```
> 其中初始顺序必须和申明顺序一致，如果初始列表中的元素个数少于类成员的个数，则靠后的成员被值初始化。且初始化列表中的元素个数不能多于成员数量。

需要注意的是，标准允许编译器在初始化过程中跳过*拷贝/移动构造函数*直接创建对象。

## 拷贝赋值运算符

*拷贝赋值运算符*接受一个与其所在类型相同的参数。如果没有定义其*拷贝赋值运算符*，编译器会为它生成一个*合成拷贝赋值运算符(synthesized copy assignment operator)*。

## 安全的拷贝赋值运算符

编写拷贝赋值运算符时，有两点需要注意：1、自我拷贝 2、异常安全。下面精心构造的例子可以说明这些问题：

```
class Bitmap { };
class Widget {
  Bitmap *pb;
  
public:
  Widget(Bitmap *p) : pb(p) {}
  
  Widget &operator = (const Widget &rhs) {
    delete pb;
    pb = new Bitmap(*rhs.pb);
    return *this;
  }
};
```

假设有某用户创建一个对象后对自己进行赋值：

```
Bitmap *b;
Widget w(b);
w = w;  // error;
```

或者编写 `Bitmap` 的设计者在内存不足时抛出异常：

```
class Bitmap {
public:
  Bitmap(const Bitmap& obj) {
    throw ...
  }
};
```

那么在 `new Bitmap` 操作失败，而原来的备份也被删除。

简单的解决方案是将*拷贝复制运算符*实现代码进行如下修改：

```
Widget &operator = (const Widget &rhs) {
  Bitmap *old = pb;
  pb = new Bitmap(*rhs.pb);
  delete old;
  return *this;
}
```

这样的代码首先保证了异常安全，并且顺带解决了自我赋值(拷贝了一份原来的数据)。另一个替代方案是 *copy and swap* 技术：

```
Widget &operator = (Widget rhs) {
  this->swap(rhs);
  return *this;
}
```

其中假设 `swap` 函数不会抛出异常。这种方法利用以下依据：

- 某 class 的 copy assignment 操作可能被申明为 “以 by value 方式接受实参”
- 以 by value 方式传递东西会造成一件副本

这种方法将 “copying” 动作从函数本体内移到 *函数参数构造阶段*。

## 对象移动

对于某些场景，比如 `vector<string>` 增长时，将旧元素拷贝到新内存是不必要的，而某些对象如 IO 类或 `unique_ptr` 则不能拷贝。为了解决这些问题，新标准引入了移动语义 - *右值引用(rvalue reference)*。

## 右值引用

所谓右值引用就是必须绑定到右值的引用，类似于任何引用，一个右值引用也不过是某个对象的另一个名字。左值和右值都是针对表达式而言的，左值是指表达式结束后依然存在的持久对象，右值是指表达式结束时就不再存在的临时对象。一个区分左值与右值的便捷方法是：看能不能对表达式取地址，如果能，则为左值，否则为右值。左值有持久状态，而右值要么是字面常量，要么是表达式求值过程中创建的临时对象，所以使用右值引用可以自由的接管所引用对象的资源。 

```
int i = 1;
int &&rr = i * 2;
```
基于可以看作是将 `i * 2` 产生的临时变量绑定到 `rr` 上。而这里的 `rr` 是右值引用，但其却是一个变量，对于这种情况，标准中提到：

> Things that are declared as rvalue reference can be lvalues or rvalues. The distinguishing criterion is: if it has a name, then it is an lvalue. Otherwise, it is an rvalue.

所以， `rr` 也是一个左值。这里也就是所谓的绑定到右值的引用。理解右值引用是理解移动语义的基础。

## 移动构造函数和移动赋值操作符

类似于*拷贝构造函数*，*移动构造函数*第一个参数必须是该类型的一个右值引用，其余参数都必须有默认实参。而*移动赋值操作符*则是接受本类型的右值。需要注意的是使用移动语义后必须保证源对象处于销毁无害的状态，即该对象拥有的资源转移给了赋值对象。所以一般的移动构造函数都会将原对象的指针等设置为 `nullptr`。

在移动操作中允许抛出异常，但是通常不会抛出异常。而标准容器库能对异常发生时其自身的行为提供保障，所以如果元素的移动构造函数没有 `noexcept` 修饰时，容器库在从新分配内存时会选择*拷贝构造函数*而不是*移动构造函数*。因此，如无必要，移动构造函数应当加 `noexcept` 修饰。

需要注意到的是合成版本的*移动构造函数*和*移动赋值操作符*合成条件比较多，这里没有涉及。如果一个类定义了右值构造，那么我们可以通过给它传递右值参数调用其移动构造函数。如果想要对左值也进行移动，这需要进行转义。这种转义可以看作 `static_cast<T&&>(lvalue);`，在标准中由 `std::move(lvaule)` 提供支持。值得一提的是，被转化的左值，其生命期并没有随着左右值的转化而改变。也就是说，其实仍然是左值，只是变相调用了移动语义。这也是前面之所以强调的*必须保证源对象处于销毁无害的状态*。所以调用 `move` 就意味着承诺：*除了对 `lvalue` 进行赋值或者销毁它以外，我们将不在使用它`。

## 成员函数与右值

与 `const` 修饰的成员函数一致，我们可以在参数列表后放置一个*引用限定符(reference qualifier)*来指定调用者是左值还是右值。引用限定符可以是 & 或 &&，分别指出 `this` 可以指向一个左值或者右值。如果一个函数已经有 `const` 修饰，那么引用修饰必须出现在其后面的位置。

## 小结

通过以上内容可以看到，C++的许多灵活性来自于其强大的类型系统和精巧的设计理念。
