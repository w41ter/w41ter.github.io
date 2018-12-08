---
title: Android asynchronized programming summary
date: 2016-10-16 21:47:48
tags: 
 - Android 
 - Java
categories: Android

---

开发过程中涉及到异步操作非常多，更确切的说不涉及的非常少。这里说一说我遇到的一些问题。

<!-- more -->

# MessageQueue、Looper、Handler 与 Thread

Thread 是最基本的调度单位，也是异步操作的基础。Thread 内有一个 MessageQueue，用与处理外部发送的 Message。Looper 则被 Thread 用于处理 MessageQueue, 并把 Message 发送给对应的 Handler。Handler 正是用来处理各种 Message，同时也是 Message 的发送者。

```
// 简单结构描述代码
class thread {
    void run {
        mLooper.loop(mQueue);
    }
}
```

在 Thread 内部，由 Looper 处理消息队列，而 Looper 中不断取出消息并发送。

```
class Looper {
    void loop(MessageQueue queue) {
        while (true) {
            Message message = queue.pop();
            if (message == null)
                return;
            message.handler.detachMessage();
        }
    }
}
```

Handler 同时是消息真正处理者，也是消息发送者。除了给当前 Thread 发送消息外，也能给其他 Thread 发送，这就奠定了多线程协作的基础。比如， Android 为我们提供了几种在 UI 线程中运行 Runable 对象的方法：

1. Activity.runOnUiThread(Runnable)
2. View.post(Runnable)
3. View.postDelayed(Runnable, long)
4. Handler

# Blocking Request & AsyncTask

Android 无时无刻不进行了大量异步操作，当我们打开一个 App 时，后台正在请求网络数据，数据库操作和图片处理等。如果这些费时的工作全部像工厂里流水线一样执行，那么阻塞在某一个异步操作上都会导致其余部分无法进展任何工作即用户眼中的程序无响应。且等到上一个步骤完成后才能进行下一步操作，这一定不是一个好的用户体验。

现在假设某个 App 需要请求网络图片资源，那么应该这么写：

```
new Thread(new Runable() {
    final Bitmap bitmap = getBitmapFromNet(url);
    runOnUiThread(new Runable() {
        renderImageView(bitmap);
    });
}).run();
```

这样写能够正确的工作，在下载期间，用户还可以与程序进行沟通。

不过，这一定不是最佳实践，实际生产环境中建议不要这么写（应该使用我们后面将会介绍的 AsyncTask 替代），下面会详细说明为什么。首先，Thread 的准备工作其实是非常耗时的。这里只展示了加载一涨图片，而实际应用中，可能由几十甚至上百张图片同时加载，而频繁的 new Thread 不仅会耗尽系统内存和计算资源，而且会增加上下文切换时间占用比。更好的方法是使用线程池。其次，异步嵌套逻辑不宜过长，更好的实践是将它封装起来。简单的例子就是"Callback Hell"。

因为上面的问题，Android 为我们提供了 AsyncTask 专门处理这种逻辑。所以在实际 Android 开发中，上面的代码应该写成下面的形式：

```
new AsyncTask() {
    protected Bitmap doInBackground(String... urls) {
        return getBitmapFromNet();
    }

    protected void onPostExecute(Bitmap bitmap) {
        renderImageView(bitmap);
    }
}
```

当然，这里的代码只是演示作用，关于 AsyncTask 详细使用说明请看 SDK。

# RxJava 和 异步流水线操作

> RxJava 在 GitHub 主页上的自我介绍是 "a library for composing asynchronous and event-based programs using observable sequences for the Java VM"（一个在 Java VM 上使用可观测的序列来组成异步的、基于事件的程序的库）。RxJava 的本质可以压缩为异步这一个词。说到根上，它就是一个实现异步操作的库，而别的定语都是基于这之上的。

RxJava 的魅力在于能够在完成复杂的逻辑工作，并极大地保持代码整洁度。关于 RxJava 的学习请看[这里](https://github.com/lzyzsd/Awesome-RxJava)。

异步流水线操作 - 其实我也不知道该怎么说明这种情况，所以就给它取了这么个名字。这个名词主要用来描述一些逻辑上是流水线执行，但是实现上涉及到异步操作比如文件操作、数据库操作还有就是网络请求。

假设你 Boss 让你每天登录网页写当天总结，几天后你再也无法忍受每天干些重复性的工作，所以你想写个程序来帮你做：

```
// 你希望敲下面几个键就能完成工作
fuck_work summary.txt
```

现在你要来实现这个程序。假设写总结的流程如下：登录 -> 编辑 -> 保存 
所以你写成了下面的代码:

```
new AsyncTask() {
    Object doInBackground() {
        // Login
    }

    void onPostExecute() {
        new AsyncTask() {
            Object doInBackground() {
                // edit
            }

            void onPostExecute() {
                new AsyncTask() {
                    Object doInBackground() {
                        // save
                    }
                }.run();
            }
        }.run();
    }
}.run();
```

上面的代码惨不忍睹，为了实现这种流水线操作你不得不忍受这种 "Callback Hell"。这里 RxJava 就可以大展身手了，你可以把代码写成下面的样子：

```
Observable.create()
    .flatMap(Task::login)
    .flatMap(Task::edit)
    .flatMap(Task::save)
    .subscribe();
```

上述代码只是简单演示，不完整。可以看到 RxJava 可以非常简单明了的表达这种逻辑，这也是我非常喜欢它的原因。

# Be cautious

异步操作不像同步操作，它并不按照人逻辑思维来进行，所以在使用的时候应该多注意避免任何可能出现的逻辑顺序假设。

比如你正在写一个网络图片浏览页面，你准备使用 ListView 来做，所以你把代码写成了下面的样子：

```
View getView(int pos, View c, ViewGroup parent) {
    // ...
    imageView = ...
    new AsyncTask() {
        Bitmap doInBackground() {
            return getBitmapFromNet()
        }

        onPostExecute(bitmap Bitmap) {
            imageView.setBitmap(bitmap);
        }
    }.run();
    // ...
    return c;
}
```

实际上上面包含了一种假想的逻辑顺序，即当图片加载完成时，ImageView 没有被挪作他用。然而用户在实际使用中，可能出现任何未知行为，其中某些行为比如稍稍滑动了一下界面，就可能导致图片显示到错误的位置上。

Last but not least, 实际生产中，如果有可用的三方库，还是不要自己造轮子吧。