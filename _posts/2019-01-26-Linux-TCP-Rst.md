---
layout: post
title: 探究 Linux 下 TCP 的 RST Packet
date: 2019-01-26 15:13
tags: 
    - Linux
    - TCP/IP
    - Socket
categories: Network
mathjax: true
---

>注：**本文结论来自网络，真实性未考究，请批判性阅读，如果谬误，请斧正。**本文所讨论内容，均假设工作环境为 Linux 服务器。

作为 TCP 不可或缺的一部分，TCP 包头的 `RST` 为 $1$ 时，表示重置，关闭异常链接。发送 RST 包关闭连接时，不必等缓冲区的包都发出去，直接就丢弃缓存区的包发送 `RST` 包。而接收端收到 `RST` 包后，也不必发送 `ACK` 包来确认。TCP 处理程序会在自己认为的异常时刻发送 `RST` 包。

```shell
14:59:23.379829 IP localhost.62412 > localhost.9490: Flags [R], seq 4127385762, win 0, length 0
```

*通过 tcpdump 观察，`Flags [R]` 表示该包携带了 `RST` 。*

`RST` 主要用在三种场景中，保证 TCP 链接的安全性，三种场景分别是：1、到不存在端口的连接请求；2、异常终止连接；3、检测半打开连接。接下来看看 `RST` 的具体表现。

# 三种错误

内核中的 TCP 协议栈将收到 `RST` 的场景分为三种，并抛出了对应的错误。

## connection refused

当内核中的 TCP 协议栈收到了 `SYN` 请求，但是该端口上没有处于监听状态，则相应 `RST`，此时 client 看到的便是 `connection refused`。

## broken pipe

> `fd` is connected to a pipe or socket whose reading end is closed.  When this happens the writing process will also receive a SIGPIPE signal.(Thus, the write return value is seen only if the program catches, blocks or ignores this signal.)

简单的说，如果**已知**远端读通道已经被关闭，而应用程序仍然在调用 `write`(2) 尝试向 socket 中写入数据，TCP 协议栈便会抛出 `broken pipe`。

## connection reset by peer

> A network connection was closed for reasons outside the control of the local host, such as by the remote machine rebooting or an unrecoverable protocol violation.

如果远端已经 `close`(2) 连接了，本地服务仍发送了数据，此时 TCP 协议栈便会抛出 `connection reset by peer`。

# broken pipe 和 connection reset by peer

无论是 `broken pipe` 还是 `connection reset by peer`，都是收到 `RST` 的表现，二者有何不同呢？

为了进一步研究，这里尝试着构建两个场景，分别重现 `broken pipe` 和 `connection reset by peer`。

## 重现 broken pipe

首先，在服务中监听端口，每个连接分多次写入数据，然后关闭连接。

```c++
int server() {
    Acceptor acceptor = Socket::create(AF_INET, SOCK_STREAM, 0);
    InetAddress address = InetAddress::parseV4("127.0.0.1", 9490);
    acceptor.bind(address);
    acceptor.listen(10);

    const char *msg1 = "hello", *msg2 = "world";
    while (true) {
        Connection conn = acceptor.accept();
        sleep(1);                        // wait client shutdown
        conn.write(msg1, strlen(msg1));  // write success, but RST recieved
        conn.write(msg2, strlen(msg2));  // throw `broken pipe`
    } // RAII close conn socket
} // RAII close acceptor socket
```

然后客户端连接到服务端，并立即关闭连接。

```c++
int client() {
    Connector connector = Socket::create(AF_INET, SOCK_STREAM, 0);
    InetAddress address = InetAddress::parseV4("127.0.0.1", 9490);
    connector.connect(address);
} // RAII close connector socket
```

通过 tcpdump 观察程序运行时请求：

```shell
$ sudo tcpdump -i lo '(src host 127.0.0.1) and (port 9490)'  -B 4096
14:59:13.376906 IP localhost.62412 > localhost.9490: Flags [S], seq 4127385760, win 43690, options [mss 65495,sackOK,TS val 168040030 ecr 0,nop,wscale 10], length 0
14:59:13.376919 IP localhost.9490 > localhost.62412: Flags [S.], seq 2306780414, ack 4127385761, win 43690, options [mss 65495,sackOK,TS val 168040030 ecr 168040030,nop,wscale 10], length 0
14:59:13.376928 IP localhost.62412 > localhost.9490: Flags [.], ack 1, win 43, options [nop,nop,TS val 168040030 ecr 168040030], length 0
14:59:13.377089 IP localhost.9490 > localhost.62412: Flags [P.], seq 1:2, ack 1, win 43, options [nop,nop,TS val 168040030 ecr 168040030], length 1
14:59:13.377223 IP localhost.62412 > localhost.9490: Flags [.], ack 2, win 43, options [nop,nop,TS val 168040030 ecr 168040030], length 0
14:59:14.377352 IP localhost.9490 > localhost.62412: Flags [P.], seq 2:3, ack 1, win 43, options [nop,nop,TS val 168040280 ecr 168040030], length 1
14:59:14.377439 IP localhost.62412 > localhost.9490: Flags [.], ack 3, win 43, options [nop,nop,TS val 168040280 ecr 168040280], length 0
// ....
14:59:22.379462 IP localhost.9490 > localhost.62412: Flags [P.], seq 10:11, ack 1, win 43, options [nop,nop,TS val 168042281 ecr 168042031], length 1
14:59:22.379489 IP localhost.62412 > localhost.9490: Flags [.], ack 11, win 43, options [nop,nop,TS val 168042281 ecr 168042281], length 0
14:59:22.379626 IP localhost.62412 > localhost.9490: Flags [F.], seq 1, ack 11, win 43, options [nop,nop,TS val 168042281 ecr 168042281], length 0
14:59:22.382190 IP localhost.9490 > localhost.62412: Flags [.], ack 2, win 43, options [nop,nop,TS val 168042282 ecr 168042281], length 0
14:59:23.379808 IP localhost.9490 > localhost.62412: Flags [P.], seq 11:12, ack 2, win 43, options [nop,nop,TS val 168042531 ecr 168042281], length 1
14:59:23.379829 IP localhost.62412 > localhost.9490: Flags [R], seq 4127385762, win 0, length 0
```

*上述 log 为实验过程中，和上面上面的代码略有出入。*

可以观察到，client `close`(2)，发送了 `FIN` 给 server，并收到了 `ACK`。server 此时再次尝试 `write`(2)，便抛出了 `broken pipe` 异常。

```c++
int main(int argc, char** argv) {
    try {
        return server();
    } catch (Exception& e) {
        cout << e.what() << endl;
        return -1;
    }
}
```

*`server` 调用方式。*

### SIGPIPE 与 broken pipe

按照预期，当 socket 抛出 `broken pipe` 时，会被最外层 `try` 和 `catch` 抓住，并输出。实际上运行结果为：

```shell
$ ./server
$ 
$ echo $?
141
$ 
```

*某次 server 端运行结果，没有任何输出，程序返回值为 $141$。*

内核中 TCP 栈如果已经接收到 `RST`，那么下一次使用 `write`(2) 时，除了会返回 `broken pipe` 外，还会产生 `SIGPIPE`，默认情况下这个信号会终止整个进程，当然你并不想让进程被 `SIGPIPE` 信号杀死。对 server 来说，为了不被 `SIGPIPE` 信号杀死，那就需要忽略 `SIGPIPE` 信号：

```c++
signal(SIGPIPE, SIG_IGN);
```

最后，让我们整体分析下 `broken pipe` 产生方式：

1. client 发送了 `FIN` 给 server；
2. server 仍给 client 发送数据，client 回复 `RST`；
3. server 收到 `RST` 后，再次给 client 发送数据；往一个已经收到 `RST` 的 socket 继续写入数据，将引起 `SIGPIPE` 信号，`write`(2) 返回 `EPIPE`。

## 重现 `connection reset by peer`

```c++
int server() {
    Acceptor acceptor = Socket::create(AF_INET, SOCK_STREAM, 0);
    InetAddress address = InetAddress::parseV4("127.0.0.1", 9490);
    acceptor.bind(address);
    acceptor.listen(10);

    while (true) {
        Connection conn = acceptor.accept();
        sleep(10);                       // 给拔网线留下足够的时间
    } // RAII close conn socket
} // RAII close acceptor socket
```

*模拟服务端断线重启。*

```c++
int client() {
    Connector connector = Socket::create(AF_INET, SOCK_STREAM, 0);
    InetAddress address = InetAddress::parseV4("127.0.0.1", 9490);
    connector.connect(address);
    sleep(120); 

    const char *msg = "hello";
    connector.write(msg, strlen(msg));
} // RAII close connector socket
```

*一段时间后，再给服务器发送请求，此时服务器已经重启。*

这里构造了这样一个场景，与客户端建立连接后，服务端由于不可抗力，比如断电，未能发送 `FIN` 给客户端。当服务器重启后，内核中 TCP 协议栈收到了客户端的数据包，回应 `RST`，此时客户端抛出 `connection reset by peer`。

```shell
$ sudo tcpdump -i lo '(src host 127.0.0.1) and (port 9490)'  -B 4096
15:43:12.638464 IP localhost.21316 > localhost.9490: Flags [S], seq 3640034867, win 43690, options [mss 65495,sackOK,TS val 168699846 ecr 0,nop,wscale 10], length 0
15:43:12.638478 IP localhost.9490 > localhost.21316: Flags [S.], seq 485213568, ack 3640034868, win 43690, options [mss 65495,sackOK,TS val 168699846 ecr 168699846,nop,wscale 10], length 0
15:43:16.639791 IP localhost.9490 > localhost.21316: Flags [P.], seq 5:6, ack 6, win 43, options [nop,nop,TS val 168700846 ecr 168700596], length 1
15:43:16.639807 IP localhost.21316 > localhost.9490: Flags [.], ack 6, win 43, options [nop,nop,TS val 168700846 ecr 168700846], length 0
15:43:17.640127 IP localhost.9490 > localhost.21316: Flags [P.], seq 6:7, ack 6, win 43, options [nop,nop,TS val 168701096 ecr 168700846], length 1
15:43:17.640137 IP localhost.21316 > localhost.9490: Flags [.], ack 7, win 43, options [nop,nop,TS val 168701096 ecr 168701096], length 0
15:43:18.170130 IP localhost.9490 > localhost.21316: Flags [R.], seq 7, ack 6, win 43, options [nop,nop,TS val 168701228 ecr 168701096], length 0
```

*某次模拟 `connection reset by peer`。*

------------

这里从读写两个角度来看 `RST`，如果已经 `ACK` 远端的 `FIN` 包：

1. `read`(2) ：返回 0，表示 eof；
2. `write`(2) ：远端返回 `RST`，抛出 `broken pipe`；

如果尚未接收到远端的 `FIN` 包，无论读写操作，收到 `RST` 时，抛出 `connection reset by peer`。

## what more ？

除了上述几个场景外，还有其他可能吗？

### 强行关闭

正常关闭 TCP 链接时，主动关闭一方会进入 `TIME_WAIT` 状态，等待 2MSL（报文段最大生存时间-Maximum Segment Lifetime，根据具体的实现不同，这个值会不同），此时该端口处于不可用状态。

解决 `TIME_WAIT` 有三种手段：

1. 设置 `SO_REUSEADDR` 和 `SO_REUSEPORT`；
2. 修改 `TIME_WAIT` 等待时长；
3. 设置 `SO_LINGER`，强行关闭。

设置 socket 选项 `SO_LINGER` 为 `(on, 0)` 后，`close`(2) 将立即向对端发送 `RST`，这种关闭方式称为“强行关闭”。而被动关闭方却不知道对端已经彻底断开，所以紧接着的读写操作，引发 `connection reset by peer`。

### 数据滞留

socket 关闭时，如果接收窗口仍有数据滞留，那么会直接发送 `RST` ，不会进入正常的 `FIN` 流程。可以参考：[TCP RST: Calling close() on a socket with data in the receive queue](http://cs.ecs.baylor.edu/~donahoo/practical/CSockets/TCPRST.pdf)。

和“强行关闭”一样，数据滞留也会导致被动关闭方引发 `connection reset by peer`，这样造成的结果是：如果你的服务各种指标正常，但是有非常多的 `connection reset by peer` 警告，可能就是服务上游超时 `close`(2) socket，而由于接收窗口仍有数据滞留，发送了 `RST`。

# References

[1] [Linux TCP 编程](/2017/05/26/Linux-TCP-%E7%BC%96%E7%A8%8B/)

[2] [网络编程中 SIGPIPE 信号](http://senlinzhan.github.io/2017/03/02/sigpipe/)

[3] [Linux 下 TCP 连接断开未发送 FIN](http://xiangruix.com/2016/01/12/tcp-closed-without-fin/)

[4] [TCP关闭连接(为什么会能Time_wait,Close_wait?)](http://itindex.net/detail/56132-tcp-time-wait)