---
title: Computer Science Knowledge System
date: 2017-06-13 23:52:08
tags: 
categories: 总结
mathjax: true
---

# 数据结构与算法

[CSKS-(一)、数据结构和算法](http://www.hashcoding.net/2017/08/26/CSKS-%E4%B8%80-%E3%80%81%E6%95%B0%E6%8D%AE%E7%BB%93%E6%9E%84%E5%92%8C%E7%AE%97%E6%B3%95/)

# 数据库

[CSKS-(二)、数据库系统](http://www.hashcoding.net/2017/08/26/CSKS-%E4%BA%8C-%E3%80%81%E6%95%B0%E6%8D%AE%E5%BA%93%E7%B3%BB%E7%BB%9F/)

# 操作系统

操作系统是管理和控制计算机硬件与软件资源的计算机程序，功能包括管理计算机系统的硬件、软件及数据资源，控制程序运行，改善人机界面，为其它应用软件提供支持，让计算机系统所有资源最大限度地发挥作用，提供各种形式的用户界面，使用户有一个好的工作环境，为其它软件的开发提供必要的服务和相应的接口等。

操作系统主要有五大功能：处理机管理（CPU）、进程管理、内存管理、设备管理和文件系统管理。

## 调度

进程时用户提交给操作系统运行的最小单元。在学术上，进程是具有一定功能的程序关于某个数据集合上的一次运行活动，是系统进行资源调度和分配的一个独立单位。除了进程，操作系统还提供了更小粒度的调度对象-线程。线程是进程的实体，是CPU调度和分派的基本单位，它是比进程更小的能独立运行的基本单位。一个进程可以有多个线程，多个线程也可以并发执行。

一般情况下，系统按照以下流程创建一个进程：

1. 分配、初始化 PCB 
2. 初始化机器寄存器
3. 拷贝、初始化内存页表
4. 从硬盘加载程序代码到内存
5. 将进程加入就绪队列
6. 进程调度时，选择该进程并切换到用户态开始执行进程

系统通过快速切换进程，让每一个进程都有一定的时间片来响应用户提交的请求；在用户的视角，好像每个进程都在同时执行一样。系统切换进程的方法叫做进程调度算法，基本的调度算法有：先来先服务、时间片轮转、短作业优先、优先级调度以及多级反馈队列调度。

除了进程切换，操作系统还负责管理进程的虚拟内存。一般情况下，系统会在硬盘上开辟一个空间作为交换区，用于在物理内存不足时选择性地交换部分虚拟页，以开辟出足够的物理空间。用于选择交换的页面的算法称为页面置换算法。基本的页面置换算法有：FIFO、第二次机会、时钟轮转、LRU 和 NRU。

_References_

- [操作系统常用调度算法-cnblogs](http://www.cnblogs.com/kxdblog/p/4798401.html)
- [操作系统核心原理-3.进程原理（上）：进程概要](http://www.cnblogs.com/edisonchou/p/5003694.html)
- [操作系统核心原理-3.进程原理（中）：进程调度](http://www.cnblogs.com/edisonchou/p/5020681.html)
- [虚拟内存详解-cnblogs](http://www.cnblogs.com/shijingjing07/p/5611579.html)
- [操作系统学习-内存管理](http://www.cnblogs.com/ranjiewen/p/7141696.html)
- [操作系统学习-虚拟内存](http://www.cnblogs.com/ranjiewen/p/7158267.html)

## 通信

线程之间共享内存，但拥有各自不同的运行栈；进程之间则相互隔离。线程之间并发需要解决的是线程同步问题，进程之间则是通信问题。

线程之间同步由四种基本操作提供：

- 原子操作
- 互斥量
- 信号量
- 条件变量

在以上四种基本操作的基础上，形成了高级通信工具。如：阻塞队列，共享内存等。

一般情况下，原子变量用于构造乐观锁，比如 `spinlock` 。其他情况下使用条件变量和互斥量结合起来足够完成任务，同时还不容易出错。如果使用信号量，需要在自己的程序里也维护计数值，而信号量本身也需要维护计数值，需要用户自己进行维护。

与信号量相比，互斥量增减了所有权的概念；锁住的互斥量只能由上锁的线程解开。信号量则没有这些限制。条件变量与信号量相比，没有了数量限制，资源数量隐含在程序的逻辑中。

信号量与另外两者的区别主要在于“同步”一词，同步可以看作两部分：一部分是等待数据的“事件”或者“通知”；另一部分是保护数据的“临界区”。信号量直接满足这两个功能，互斥锁与信号量各满足一部分。在 `do one thing and do it best` 的指导下，更建议使用后两者。linux 内核曾将信号量作为同步原语，后来将之换为了互斥锁，需要“通知”的场景则换成了条件变量，不仅代码变简单了，速度也上去了。

进程之间通信常用的方式有：

- 管道
- 共享内存
- 信号
- 消息队列
- socket
- RPC(Remote Process Call)

其中管道、信号、共享内存和消息队列只能运行在一台机器上，而 socket 和 RPC 则提供了远程支持。当然，也有在 socket 或 RPC 基础上实现消息队列的。一般需要实现进程间通信，可以直接考虑 socket 或 RPC，毕竟以后的业务场景有可能扩展到多机。

_References_

- [操作系统核心原理-3.进程原理（下）：进程通信](http://www.cnblogs.com/edisonchou/p/5022508.html)

## 死锁

在两个或者多个并发进程中，如果每个进程持有某种资源而又等待其它进程释放它或它们现在保持着的资源，在未改变这种状态之前都不能向前推进，称这一组进程产生了死锁。通俗的讲就是两个或多个进程无限期的阻塞、相互等待的一种状态。

死锁产生的四个条件（有一个条件不成立，则不会产生死锁）

1. 互斥条件：一个资源一次只能被一个进程使用
2. 请求与保持条件：一个进程因请求资源而阻塞时，对已获得资源保持不放
3. 不剥夺条件：进程获得的资源，在未完全使用完之前，不能强行剥夺
4. 循环等待条件：若干进程之间形成一种头尾相接的环形等待资源关系

只要上述一个条件不成立，就不会产生死锁，所以解决死锁的基本方法有：：预防死锁、避免死锁、检测死锁、解除死锁。其常用策略为：鸵鸟策略、预防策略、避免策略、检测与解除死锁。

## Linux 

_References_

- [Linux man](http://man.linuxde.net/)
- [第十二章、學習 Shell Scripts](http://linux.vbird.org/linux_basic/0340bashshell-scripts.php)

# 计算机网络

[计算机网网络总结](http://www.jianshu.com/p/8013477d344a)

## 从 URL 到页面的过程

// TODO:

## 分层与协议

### TCP 

TCP 是面向连接的、可靠的流式通信传输协议；UDP 是无连接的、不可靠的通信协议。

[Nagle 算法](http://blog.163.com/li_xiang1102/blog/static/607140762011111103213616/)
[糊涂窗口综合症和 Nagle 算法](http://www.cnblogs.com/zhaoyl/archive/2012/09/20/2695799.html)
[Nagle & Delayed ACK](https://my.oschina.net/xinxingegeya/blog/485643)
[Delayed ACK](http://blog.csdn.net/wdscq1234/article/details/52430382)
[Linux TCP 编程](http://www.hashcoding.net/2017/05/26/Linux-TCP-%E7%BC%96%E7%A8%8B/)

拥塞控制
流量控制
滑动窗口

### UDP

[可靠 UDP 传输](http://blog.codingnow.com/2016/03/reliable_udp.html)

### HTTP

HTTP（超文本传输协议，HyperText Transfer Protocol)是互联网上应用最为广泛的一种网络协议。所有的 WWW 文件都必须遵守这个标准。设计HTTP 最初的目的是为了提供一种发布和接收 HTML 页面的方法。是用于从 WWW 服务器传输超文本到本地浏览器的传输协议。默认使用 80 端口，HTTP 客户端发起一个请求，建立一个到服务器指定端口（默认是 80 端口）的 TCP 连接。

HTTP 连接使用的是“请求—响应”的方式，不仅在请求时需要先建立连接，而且需要客户端向服务器发出请求后，服务器端才能回复数据。HTTP/1.0 是第一个在通讯中指定版本号的 HTTP 协议版本，至今仍被广泛采用，特别是在代理服务器中。HTTP/1.1 是当前版本，持久连接被默认采用，并能很好地配合代理服务器工作，还支持以管道方式同时发送多个请求，以便降低线路负载，提高传输速度。 HTTP／2.0 在 HTTP 1.x 的基础上，大幅度的提高了 web 性能，减少了网络延迟。HTTP1.0 和 1.1 在之后很长的一段时间内会一直并存，这是由于网络基础设施更新缓慢所决定的。

关于更多 HTTP 协议的基础信息，可以看[HTTP基础](http://www.jianshu.com/p/80e25cb1d81a)、[HTTP 请求方法和幂等性探究](http://www.jianshu.com/p/178da1e2903c)、[理解 HTTP 幂等性](http://www.cnblogs.com/weidagang2046/archive/2011/06/04/2063696.html)。

HTTP 以 TCP 作为传输协议，自然要面临链接管理的问题，[HTTP连接管理](http://www.jianshu.com/p/f424eb4175ac)、[谈谈 HTTP 连接管理](http://www.jianshu.com/p/1102f00002ff)。

另外，随着网络访问量的提升，性能瓶颈问题开始出现。HTTP 对于这部分问题的解决办法是：对固定的资源进行缓存。HTTP 缓存通常分为：强制缓存、对比缓存。关于 HTTP 缓存的具体内容参考：[HTTP缓存机制](http://www.cnblogs.com/chenqf/p/6386163.html)。

最后，关于 HTTP 协议中常见的两种攻击方式：[用大白话谈谈XSS与CSRF](https://segmentfault.com/a/1190000007059639)。

_References_

- [HTTP 2.0 资料汇总](https://imququ.com/post/http2-resource.html)

## SSL/TLS

[SSL/TLS 原理详解](https://segmentfault.com/a/1190000002554673)。

## IO 模型

// TODO:

## 分布式

### CAP 理论和 BASE 理论

_References_

- [CAP 理论](http://blog.csdn.net/chen77716/article/details/30635543)
- [CAP 理论和最终一致性](http://blog.csdn.net/dc_726/article/details/42784237)
- [最终一致性实现方式](https://zhuanlan.zhihu.com/p/25933039?utm_source=tuicool&utm_medium=referral)
- [CAP 理论和 BASE 理论](http://www.cnblogs.com/duanxz/p/5229352.html)

### 一致性 Hash

_References_

- [每天进步一点点——五分钟理解一致性哈希算法(consistent hashing)](http://blog.csdn.net/cywosp/article/details/23397179)
- [一致性Hash算法原理](http://www.cnblogs.com/lpfuture/p/5796398.html)
- [一致性Hash算法Java实现](http://www.blogjava.net/hello-yun/archive/2012/10/10/389289.html)

# 设计模式
 
[CSKS-(三)、设计模式](http://www.hashcoding.net/2017/08/26/CSKS-%E4%B8%89-%E3%80%81%E8%AE%BE%E8%AE%A1%E6%A8%A1%E5%BC%8F/)

# 语言

## C++

_References_

- [C++11 标准基本数据类型](http://blog.csdn.net/itmr_liu/article/details/51869905)

### 类型转换

_References_

- [C++11 四种类型转换](http://www.cnblogs.com/BeyondAnyTime/archive/2012/08/23/2652696.html)
- [C++笔记 · C++类型转换](https://zhuanlan.zhihu.com/p/27966225)

### 最佳实践

_References_

- [Accustoming Yourself to C++](www.hashcoding.net/2017/03/02/Effective-C-Accustoming-Yourself-to-C/)
- [Constructors,Destructors,and Assignment Operators](www.hashcoding.net/2017/03/02/Effective-c-Constructors-Destructors-and-Assignment-Operators/)
- [Resource management](www.hashcoding.net/2017/03/05/Effective-C-Resource-management/)
- [Designs & Implements](www.hashcoding.net/2017/03/05/Effective-C-Designs-Implements/)
- [Exception-safe code](www.hashcoding.net/2017/03/05/Effective-C-Exception-safe-code/)
- [C++对象线程安全](www.hashcoding.net/2017/01/15/C-%E5%AF%B9%E8%B1%A1%E7%BA%BF%E7%A8%8B%E5%AE%89%E5%85%A8/)

### C++ 疑难解答

_References_

- [取余和取模](http://blog.csdn.net/origin_lee/article/details/40541053)
- [带符号整数的除法和余数](http://blog.csdn.net/solstice/article/details/5139302)
- [C++并发编程那些事](http://0xffffff.org/2016/02/11/38-c++-concurrency/)
- [深入理解右值引用-move语义和完美转发](http://blog.csdn.net/booirror/article/details/45057689)
- [C++完全总结](http://www.cnblogs.com/jianxinzhou/p/3994248.html)

## Java

### 类加载原理

Java和其他语言不同的是，Java是运行于Java虚拟机(JVM)。这就意味着编译后的代码是以一种和平台无关的格式保存的，而不是某种特定的机器上运行的格式。这种格式和传统的可执行代码格式有很多重要的区别。具体来说，不同于C或者Ｃ++程序，Java程序不是一个独立的可执行文件，而是由很多分开的类文件组成，每个类文件对应一个Java类。另外，**这些类文件并不是马上加载到内存，而是当程序需要的时候才加载**。类加载器就是Java虚拟机中用来把类加载到内存的工具。

Class文件由类装载器装载后，在JVM中将形成一份描述Class结构的元信息对象，通过该元信息对象可以获知Class的结构信息：如构造函数，属性和方法等，Java允许用户借由这个Class相关的元信息对象间接调用Class对象的功能。虚拟机把描述类的数据从class文件加载到内存，并对数据进行校验，转换解析和初始化，最终形成可以被虚拟机直接使用的Java类型，这就是虚拟机的类加载机制。

#### 工作机制

类装载器就是寻找类的字节码文件，并构造出类在JVM内部表示的对象组件。在Java中，类装载器把一个类装入JVM中，要经过以下步骤：

1. 装载：查找和导入Class文件；
2. 链接：把类的二进制数据合并到JRE中；
    - 校验：检查载入Class文件数据的正确性；
    - 准备：给类的静态变量分配存储空间；
    - 解析：将符号引用转成直接引用；
3. 初始化：对类的静态变量，静态代码块执行初始化操作

#### 类初始化时机

1. 遇到 `new`、`getstatic`、`putstatic` 或 `invokestatic` 这4条字节码指令时，如果类没有进行过初始化，则需要先触发其初始化。生成这4条指令的最常见的Java代码场景是：使用 `new` 关键字实例化对象的时候，读取或设置一个类的静态字段（被 `final` 修饰、已在编译期把结果放入常量池的静态字段除外）的时候，以及调用一个类的静态方法的时候。
2. 使用 `java.lang.reflect` 包的方法对类进行反射调用的时候，如果类没有进行过初始化，则需要先触发其初始化。
3. 当初始化一个类的时候，如果发现其父类还没有进行过初始化，则需要先触发其父类的初始化。
4. 当虚拟机启动时，用户需要指定一个要执行的主类（包含 `main()` 方法的那个类），虚拟机会先初始化这个主类。

只有上述四种情况会触发初始化，也称为对一个类进行主动引用，除此以外，所有其他方式都不会触发初始化，称为被动引用。

### 数据类型

Java 中数据类型分为两种：基本数据类型，引用数据类型。

#### 基础数据类型

基础数据类型由数值型、字符型和布尔型组成，其中数值型有：

- byte 
- short
- int 
- long 
- float 
- double 

字符型：`char` 可以表示任意有 `unicode` 编码的值，2字节长度。布尔型 `boolean` 表示逻辑运算类型。

`char` 本质上是 UTF-16 定常编码，换而言之，`char` 中只能存放 `UTF-16` 编码下只占2字节长度的字符。

##### 自动类型转换

**自动类型转换，也称隐式类型转换，是指不需要书写代码，由系统自动完成的类型转换**。由于实际开发中这样的类型转换很多，所以 Java 语言在设计时，没有为该操作设计语法，而是由 JVM 自动完成。

转换规则：从存储范围小的类型到存储范围大的类型。
具体规则为：byte→short(char)→int→long→float→double

也就是说 byte 类型的变量可以自动转换为 short 类型，示例代码：

```java
byte  b  =  10;
short  sh  =  b;
```

这里在赋值时，JVM 首先将 `b` 的值转换为 `short` 类型，然后再赋值给 `sh`。
在类型转换时可以跳跃。示例代码：

```java
byte  b1  =  100;
int  n  =  b1;
```

类型转换中可能存在着坑：

```java
short a = 0;
a = a + 1; // error
a += 1;
```

执行 `+1` 时，`a` 被转换为整形，然后做加法，赋值给 `a` 时类型不一致，需要强制类型转换；而 `+=` 则由编译器内部实现 `+1` 逻辑。

> 注意问题:在整数之间进行类型转换时，数值不发生改变，而将整数类型，特别是比较大的整数类型转换成小数类型时，由于存储方式不同，有可能存在数据精度的损失。

##### 强制类型转换

**强制类型转换，也称显式类型转换，是指必须书写代码才能完成的类型转换**。该类类型转换很可能存在精度的损失，所以必须书写相应的代码，并且能够忍受该种损失时才进行该类型的转换。

转换规则:从存储范围大的类型到存储范围小的类型。
具体规则为：double→float→long→int→short(char)→byte
语法格式为：(转换到的类型)需要转换的值

示例代码：

```java
double  d  =  3.10;
int  n  =  (int)d;
```

这里将 `double` 类型的变量 `d` 强制转换成 `int` 类型，然后赋值给变量 `n`。需要说明的是小数强制转换为整数，采用的是**去 1 法**，也就是无条件的舍弃小数点的所有数字，则以上转换出的结果是 `3`。整数强制转换为整数时取数字的低位，例如 `int` 类型的变量转换为 `byte` 类型时，则只去 `int` 类型的低 `8` 位(也就是最后一个字节)的值。
示例代码：

```java
int  n  =  123;
byte  b  =  (byte)n;
int  m  =  1234;
byte  b1  =  (byte)m;
```

则 `b` 的值还是 `123`，而 `b1` 的值为 `-46`。`b1` 的计算方法如下：`m` 的值转换为二进制是 `10011010010`，取该数字低 `8` 位的值作为 `b1` 的值，则 `b1` 的二进制值是 `11010010`，按照机器数的规定，最高位是符号位，`1` 代表负数，在计算机中负数存储的是补码，则该负数的原码是 `10101110`，该值就是十进制的 `-46`。

> 注意问题:强制类型转换通常都会存储精度的损失，所以使用时需要谨慎。

#### 引用数据类型

引用数据类型有三大类：

- 接口
- 对象
- 数组

引用数据类型也存在着自动转换和强制类型转换，自动转换负责将子类对象转换成父类对象，强制转换则将父类对象转换成子类对象。

### Object 

`java.lang` 包在使用的时候无需显示导入，编译时由编译器自动导入。`Object` 类是类层次结构的根，Java 中所有的类从根本上都继承自这个类。`Object` 类是 Java 中唯一没有父类的类。其他所有的类，包括标准容器类，比如数组，都继承了 `Object` 类中的方法。

`Object` 类中有如下方法：

#### clone()

`clone` 方法**创建并返回对象的一份拷贝**，其原型如下：

```java
protected Object clone() throws CloneNotSupportedException
```

这个方法有两点比较特殊的：

- 使用这个方法的类必须实现 `java.lang.Cloneable` 接口，否则会抛出 `CloneNotSupportedException` 异常。`Cloneable` 接口中不包含任何方法，所以实现它时只要在类声明中加上 `implements` 语句即可；
- 这个方法是 `protected` 修饰的，覆写 `clone()` 方法的时候需要写成 `public`，才能让类外部的代码调用；

#### equals(Object obj)

`equals` 方法等价于 `==` 运算符，用于判断两个对象是否指向同一个对象。

> 在 Java 中，`==` 运算符默认使用**引用语义**，即比较两个对象是否引用同一对象；C/C++ 相反，默认使用**值语义**，比较内部数据是否相同。

`Object` 类中的 `equals()` 方法如下：

```java
public boolean equals(Object obj) {
    return (this == obj);
}
```
即 `Object` 类中的 `equals()` 方法等价于 `==`，只有当继承 `Object` 的类覆写（`override`）了 `equals()` 方法之后，继承类实现了用 `equals()` 方法比较两个对象是否相等，才可以说 `equals()` 方法与 `==` 不同。比如 `String` 类覆写了 `equals()` 方法，实现了**值语义**。

`equals()` 方法需要具有如下特点：

- 自反性：任何非空引用 `x`，`x.equals(x)`返回为 `true`;
- 对称性：任何非空引用 `x` 和 `y`，`x.equals(y)` 返回 `true` 当且仅当 `y.equals(x)` 返回 `true`;
- 传递性：任何非空引用 `x` 和 `y`，如果 `x.equals(y)` 返回 `true`，并且 `y.equals(z)` 返回 `true`，那么 `x.equals(z)` 返回 `true`。
- 一致性：两个非空引用 `x` 和 `y`，`x.equals(y)` 的多次调用应该保持一致的结果，（前提条件是在多次比较之间没有修改 `x` 和 `y` 用于比较的相关信息）。
- 约定：对于任何非空引用 `x`，`x.equals(null)` 应该返回为 `false`。
- 并且覆写 `equals()` 方法时，应该同时覆写 `hashCode()` 方法，反之亦然。

前面三个特点属于**等价关系**需要满足的条件，所以**对于任何非空引用，`equals()` 方法定义了该引用上的等价关系**。

#### hashCode()

`hashCode()` 返回当前对象的 `hash code`，原型如下： 

```
int	hashCode()
```

这个方法返回一个整型值（hash code value），如果两个对象被 `equals()` 方法判断为相等，那么它们就应该拥有同样的hash code。

`Object` 类的 `hashCode()` 方法为不同的对象返回不同的值，`Object` 类的 `hashCode` 值表示的是对象的地址。

`hashCode` 方法需要满足一定条件：

1. 一致性：`hashCode()` 方法多次执行结果应该相同（未修改时）；
2. 当你覆写了 `equals()` 方法之后，必须也覆写 `hashCode()` 方法，反之亦然；
3. 如果 `equals()` 判断两个对象不相等，那么它们的 `hashCode()` 方法就应该返回不同的值（未强制要求）；

两个对象用 `equals()` 方法比较返回 `false`，它们的 `hashCode` 可以相同也可以不同。

#### toString()

`toString()` 方法返回对象的 `String` 表示。当打印引用，如调用 `System.out.println()` 时，会自动调用对象的 `toString()` 方法，打印出引用所指的对象的 `toString()` 方法的返回值，因为每个类都直接或间接地继承自 `Object`，因此每个类都有 `toString()` 方法。

`Object` 类中的 `toString()` 方法定义如下：

```java
public String toString() {
    return getClass().getName() + "@" + Integer.toHexString(hashCode());
}
```

#### finalize()

_References_

- [Java finalize() 方法详解](http://www.cnblogs.com/iamzhoug37/p/4279151.html)

#### getClass() 

_References_

- [Java getClass() 方法详解](http://www.cnblogs.com/lianghui66/archive/2012/12/03/2799134.html)

#### Others

_References_

- [Java Object wait()、notify()、notifyAll()](http://blog.csdn.net/zimo2013/article/details/40181349)

### 泛型

_References_

- [Java 泛型基础](http://www.jianshu.com/p/c8ac39183522)
- [Java 泛型 <? super T> 中 super 怎么 理解？与 extends 有何不同？](https://www.zhihu.com/question/20400700)
- [Java 泛型进阶](http://www.jianshu.com/p/4caf2567f91d)
- [浅谈 Java 泛型](http://www.jianshu.com/p/b99a40c1f760)

### Array

数组比较特殊，其有一个 `length` 成员，表示数组长度。

_References_

- [Java 数组操作](http://www.iteye.com/news/28296)
- [Java Arrays 详解](http://www.jianshu.com/p/355d6416c26c)

### String

_References_

- [String 类常用方法详解](http://www.cnblogs.com/springcsc/archive/2009/12/03/1616326.html)
- [String 类详解](http://www.cnblogs.com/lwbqqyumidi/p/4060845.html)
- [String StringBuffer StringBuilder 详解](http://blog.csdn.net/kingzone_2008/article/details/9220691)

### Collection

`Collection`是Java中的集合类的一个抽象接口，在其上有更具体的接口实现：`Set`和`List`。

_References_

- [Java Collection 详解](http://www.jianshu.com/p/f23ec9da6ecf)

#### Set

`Set`中方法与`Collection`一致。

1. `HashSet`：内部数据结构是哈希表，是不同步的。`Set`集合中元素都必须是唯一的，`HashSet`作为其子类也需保证元素的唯一性。
    判断元素唯一性的方式：
    通过存储对象（元素）的`hashCode`和`equals`方法来完成对象唯一性的。
    如果对象的`hashCode`值不同，那么不用调用`equals`方法就会将对象直接存储到集合中；
    如果对象的`hashCode`值相同，那么需调用`equals`方法判断返回值是否为`true`，
    若为`false`, 则视为不同元素，就会直接存储；
    若为`true`， 则视为相同元素，不会存储。
        
    PS：如果要使用`HashSet`集合存储元素，该元素的类必须覆盖`hashCode`方法和`equals`方法。一般情况下，如果定义的类会产生很多对象，通常都需要覆盖`equals`，`hashCode`方法。建立对象判断是否相同的依据。
    
2. `TreeSet`：保证元素唯一性的同时可以对内部元素进行排序，是不同步的。
    判断元素唯一性的方式：
    根据比较方法的返回结果是否为0，如果为0视为相同元素，不存；如果非0视为不同元素，则存。
    `TreeSet`对元素的排序有两种方式：
    方式一：使元素（对象）对应的类实现`Comparable`接口，覆盖`compareTo`方法。这样元素自身具有比较功能。
    方式二：使`TreeSet`集合自身具有比较功能，定义一个类实现`Comparable`接口覆盖其`compareTo`方法。（相当于自定义了一个比较器）将该类对象作为参数传递给`TreeSet`集合的构造函数。（`TreeSet(Comparator<? super E> c)`）

#### Map

`Map`保存具有映射关系的数据，因此`Map`集合里保存着两组值，一组值用来保存`Map`里的`key`,一组用来保存`Map`里的`value`,`key`和`value`可以是任何引用类型的数据。

`Map`里的`key`不允许重复，`value`可以重复。`key`和`value`之间存在单向的一对一的关系，通过指定的`key`，总能找到唯一的、确定的`value`。

##### HashMap与HashTable

`HashMap`与`HashTable`都是`Map`的典型实现类，他们之间的关系类似于`ArrayList`和`Vector`：`HashTable`是一个古老的`Map`实现类，在JDK1.0时就出现了。
主要区别：

1. `HashTable`是一个线程安全的`Map`实现，但是`HashMap`是线程不安全的实现，`HashMap`的性能要比`HashTable`高一些，尽量避免使用`HashTable`,多个线程访问一个`Map`对象又要保证线程安全时，可以使用`Collections`中的方法把`HashMap`变成线程安全的。

2. `HashTable`不允许使用`null`作为`key`和`value`,如果试图把`null`加入`HashTable`中，将会引发空指针异常。

##### TreeMap

`TreeMap`是`Map`的子接口`SortedMap`的的实现类，与`TreeSet`类似的是`TreeMap`也是基于红黑树对`TreeMap`中所有的`key`进行排序，从而保证`key-value`处于有序状态，`TreeMap`也有两种排序方式：

1. 自然排序：`TreeMap`的所有`key`必须实现`Comparable`接口，而且所有`key`应该是同一类的对象，否则会抛出`ClassCastException`.

2. 定制排序：创建`TreeMap`时，传入一个`Comparator`对象，该对象负责对`TreeMap`中所有的`key`进行排序。
由于`TreeMap`支持内部排序，所以通常要比`HashMap`和`HashTable`慢。

#### Queue

`Queue`模拟了队列这种数据结构，队列通常是“先进先出”的数据结构，通常不允许随机访问队列中的元素。

`Queue`常用的实现类：`LinkedList`和`PriorityQueue`。

##### LinkedList

`LinkedList`它不仅实现了`List`接口还实现了`Dueue`接口(双端队列，既具有队列的特征，也具有栈的特征)，`Dueue`接口是`Queue`的子接口。

##### PriorityQueue

`PriorityQueue`保存队列元素的的顺序并不是按照加入队列的顺序，而是按照队列元素大小进行重新排序。所以当调用`peek`和`poll`方法来取队列中的元素的时候，并不是先取出来队列中最小的元素。从这个意义上来看，`PriorityQueue`已经违反了队列的基本规则。`PriorityQueue`不允许插入`null`元素。

### Concurrent 

_References_

- [Java 并发工具包 `java.util.concurrent` 用户指南](http://blog.csdn.net/defonds/article/details/44021605/)

## Python

_References_

- [Python3 教程](http://www.liaoxuefeng.com/wiki/0014316089557264a6b348958f449949df42a6d3a2e542c000)

# 系统设计

_References_

- [系统设计入门](https://github.com/donnemartin/system-design-primer/blob/master/README-zh-Hans.md)

# Others

## Markdown 

_References_

- [Markdown-语法手册](http://blog.leanote.com/post/freewalk/Markdown-语法手册 "Markdown-语法手册")
- [Markdown-书写风格指南](http://einverne.github.io/markdown-style-guide/zh.html)

## Latex 

_References_
- [Latex 数学公式](http://lixingcong.github.io/2016/04/04/LaTex-intro/)

## 需要补充

分布式架构：（了解原理就行，如果真的有实践经验更好）                  
CAP原理和BASE理论。                   
Nosql与KV存储（redis，hbase，mongodb，memcached等）                   
服务化理论（包括服务发现、治理等，zookeeper、etcd、springcloud微服务、）                   
负载均衡（原理、cdn、一致性hash）                   
RPC框架（包括整体的一些框架理论，通信的netty，序列化协议thrift，protobuff等）                   
消息队列（原理、kafka，activeMQ，rocketMQ）                   
分布式存储系统（GFS、HDFS、fastDFS）、存储模型（skipList、LSM等）                   
分布式事务、分布式锁等                        

大数据与数据分析：                  
hadoop生态圈(hive、hbase、hdfs、zookeeper、storm、kafka)                   
spark体系                   
语言：python、R、scala                   
搜索引擎与技术                        
机器学习算法：                  
模型和算法很多。                        
其他工具的理论和使用：                  
这个更多了，问的多的比如git、docker、maven/gradle、Jenkins等等


[常见面试题整理--数据库篇](https://zhuanlan.zhihu.com/p/23713529)
[常见面试题整理--操作系统篇](https://zhuanlan.zhihu.com/p/23755202)
[Java 面试题全集-上](http://www.importnew.com/22083.html)
[Java 面试题全集-下](http://www.importnew.com/22087.html)
[常见面试题整理 Python 概念篇](https://zhuanlan.zhihu.com/p/23526961)
[常见面试题整理 Python 代码篇](https://zhuanlan.zhihu.com/p/23582996)
[常见面试题整理--计算机网络篇](https://zhuanlan.zhihu.com/p/24001696)
[计算机网络基础面试题](http://www.jianshu.com/p/7274615afea6)
