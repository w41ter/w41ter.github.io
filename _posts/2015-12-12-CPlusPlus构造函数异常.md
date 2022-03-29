---
layout: post
title: 'C++:构造函数异常'
date: 2015-12-12 21:51:34
tags: C++
categories: C++
---

C++语言认为：一个对象在出生的过程中发生异常问题，那这个对象就是一个没有生命的怪胎。既然它不是一个完整的对象，就根本不存在析构或释放的说法。因此，C++在执行构造函数过程中产生异常时，是不会调用对象的析构函数的，而仅仅清理和释放产生异常前的那些C++管理的变量空间等，之后就把异常抛给程序员处理。所以构造函数失败时，说明构造出的对象不是一个完整的对象，如果严重，可能要直接终止程序，或通过修正改参数等重新构造，总而言之，要在构造函数内部把问题解决。

<!-- more -->

对于C++语言来说，由于构造函数产生异常时不会调用对应的析构函数，那么在构造函数里发生异常前的代码所创建的其他东西就不能被析构函数内的相关释放代码所释放。例如：

	class throw_ {
	public:
		throw_() { ... }
	};
	
	class Object {
	public:
		Object() data(new int[100]) {
			throw_ t = throw_();
		}
		~Object() {
			delete []data;
		}
	private:
		int *data;
	};

`throw_`类的构造函数没有承若不抛出异常，所以这段代码中`data`指向的内存空间不能得到释放。除此之外，还有下面这种情况也会抛出异常:

	class Object {
	public:
		Object() {
			for (size_t i = 0; i < 100; ++i) {
				data[i] = nullptr;
			}
			
			//...
			
			for (size_t i = 0; i < 100; ++i) {
				data[i] = new int[1024 * 1024 * 1024];
			}
		}
		~Object() {
			for (size_t i = 0; i < 100; ++i) {
				delete []data[i];
			}
		}
	private:
		int *data[100];
	};
			
如果在申请空间的时候抛出：bad_alloc 异常，那么前面申请的内存将得不到释放，造成内存泄漏。这样可以改写如下：

	try {
		throw_ t = throw_();
	} catch (Exception &e) {
		delete []data;
		throw e;
	}

但是这么做只会使你的代码看上去混乱,而且会降低效率,这也是一直以来异常名声不大好的原因之一. 请借助于RAII技术来完成这样的工作:

	class throw_ {
	public:
		throw_() { ... }
	};
	
	class Object {
	public:
		Object() data(make_shared(new int[100])) {
			throw_ t = throw_();
		}
		~Object() { }
	private:
		shared_ptr<int> data;
	};
	
能这样做的原因是构造函数抛出异常时，已经构造的成员会逆序析构。

最后，其他人总结：

1. C++中通知对象构造失败的唯一方法那就是在构造函数中抛出异常；
2. 构造函数中抛出异常将导致对象的析构函数不被执行；
3. 当对象发生部分构造时，已经构造完毕的子对象将会逆序地被析构；