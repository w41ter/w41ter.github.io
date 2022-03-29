---
layout: post
title: Clang for windows
date: 2015-12-23 21:27:06
tags: Compile
---

G++ 编译产生的错误信息非常不人性化，所以准备转到 Clang，在这中途折腾了许久，仅仅是为了将 Clang 安装在 windows 上。所以在这里记录下该过程，以后再遇到相关问题可以快速解决。

<!-- more -->

## Clang 

Clang 是一个 C 语言、C++、Objective-C、Objective-C++ 语言的轻量级编译器，相对于 GCC ，其编译速度更快，编译产出错误提示更友好。

## 安装

这里介绍的安装方法需要下面的工具，CMake、GIT、VisualStudio。有关于 CMake 的介绍，可以看[CMake入门](http://www.hahack.com/codes/cmake/)。git 是一个免费的、分布式的版本控制工具，或是一个强调了速度快的源代码管理工具。Git最初被Linus Torvalds开发出来用于管理Linux内核的开发。关于 git 入门教程可以参考[git快速入门](http://www.bootcss.com/p/git-guide/)。

首先是下载 Clang 的源代码，Clang 编译需要依赖 llvm。

```
mkdir llvm
cd llvm
git clone http://llvm.org/git/llvm.git
mv llvm source
cd source/tools
git clone http://llvm.org/git/clang.git
```

现在使用CMake将其转换为VS工程。

```
cd ../../
mkdir debug+asserts
cd debug+asserts
cmake -G "Visual Studio 14" ../source -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DLLVM_ENABLE_ASSERTIONS=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo
```
这样，等待相关信息准备完毕后，就会在当前目录下就会生成 VS 工程。这里我使用的是 VS2015 ，你在自己使用的时候，需要针对性的修改一下。

现在可以打开进行编译，普通的机器编译过程比较长.