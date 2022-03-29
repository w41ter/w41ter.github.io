---
layout: post
title: SO_REUSEADDR & SO_REUSEPORT 异同
date: 2017-06-04 11:26:20
tags: Socket
---

2018-1-15 日更新：这里贴上 `man 7 socket` 中对 `SO_REUSEADDR` 和 `SO_REUSEPORT` 的说明，大有裨益。

- `SO_REUSEADDR`

Indicates  that  the rules used in validating addresses supplied in a `bind`(2) call should allow
reuse of local addresses.  For `AF_INET` sockets this means that a socket may bind,  except  when
there  is  an active listening socket bound to the address.  When the listening socket is bound
to `INADDR_ANY` with a specific port then it is not possible to bind to this port for  any  local
address.  Argument is an integer boolean flag.

- `SO_REUSEPORT` (since Linux 3.9)

Permits  multiple `AF_INET` or `AF_INET6` sockets to be bound to an identical socket address.  **This
option must be set on each socket (including the first socket) prior to calling `bind`(2) on  the
socket**.   To prevent port hijacking, all of the processes binding to the same address must have
the same effective UID.  This option can be employed with both TCP and UDP sockets.

For TCP sockets, this option allows `accept`(2) load distribution in a multi-threaded  server  to
be  improved  by using a distinct listener socket for each thread.  This provides improved load
distribution as compared to traditional techniques such using a single `accept`(2)ing thread that
distributes  connections,  or  having  multiple threads that compete to `accept`(2) from the same
socket.

For UDP sockets, the use of this option can provide better distribution of  incoming  datagrams
to  multiple processes (or threads) as compared to the traditional technique of having multiple
processes compete to receive datagrams on the same socket.

**写在前面，本文转载自网络：http://blog.chinaunix.net/uid-28587158-id-4006500.html ，请保留出处。**

文章内容来源于stackoverflow上的回答，写的很详细http://stackoverflow.com/questions/14388706/socket-options-so-reuseaddr-and-so-reuseport-how-do-they-differ-do-they-mean-t

虽然不同的系统上socket的实现方式有一些差异，但都来源于对BSD socket的实现，因此在讨论其它系统之前了解BSD socket的实现是非常有益的。首先我们需要了解一些基本知识，一个TCP/UDP连接是被一个五元组确定的：

```
{<protocol>, <src addr>, <src port>, <dest addr>, <dest port>}
```

因此，任何两个连接都不可能拥有相同的五元组，否则系统将无法区别这两个连接。

当使用`socket()`函数创建套接字的时候，我们就指定了该套接字使用的protocol(协议)，`bind()`函数设置了源地址和源端口号，而目的地址和目的端口号则由`connect()`函数设定。尽管允许对UDP进行"连接"（在某些情况下这对应用程序的设计非常有帮助）但由于UDP是一个无连接协议，UDP套接字仍然可以不经连接就使用。"未连接"的UDP套接字在数据被第一次发送之前并不会绑定，只有在发送的时候被系统自动绑定，因此未绑定的UDP套接字也就无法收到（回复）数据。未绑定的TCP也一样，它将在连接的时候自动绑定。

如果你明确绑定一个socket，把它绑定到端口0是可行的，它意味着"any port"("任意端口")。**由于一个套接字无法真正的被绑定到系统上的所有端口，那么在这种情况下系统将不得不选择一个具体的端口号（指的是"any port"）**。源地址使用类似的通配符，也就是"any address" （IPv4中的0.0.0.0和IPv6中的::）。**和端口不同的是，一个套接字可以被绑定到任意地址(any address)，这里指的是本地网络接口的所有地址**。由于socket无法在连接的时候同时绑定到所有源IP地址，因此当接下来有一个连接过来的时候，系统将不得不挑选一个源IP地址。考虑到目的地址和路由表中的路由信息，系统将会选择一个合适的源地址，并将任意地址替换为一个选定的地址作为源地址。

默认情况下，任意两个socket都无法绑定到相同的源IP地址和源端口(即源地址和源端口号均相同)。只要源端口号不相同，那么源地址实际上没什么关系。将socketA绑定到地址A和端口X （A:X)，socketB绑定到地址B和端口Y (B:Y)，只要`X != Y`，那么这种绑定都是可行的。然而当`X == Y`的时候只要`A != B`，这种绑定方式也仍然可行，比如：一个FTP server的socketA绑定为192.168.0.1:21而属于另一个FTP server的socketB绑定为 10.0.0.1:21，这两个绑定都将成功。记住：**一个socket可能绑定到本地"any address"。例如一个socket绑定为 0.0.0.0:21，那么它同时绑定了所有的本地地址，在这种情况下，不论其它的socket选择什么特定的IP地址，它们都无法绑定到21端口，因为0.0.0.0和所有的本地地址都会冲突。**

上面说的对所有主流操作系统都是一样的。当涉及到地址重用的时候，OS之间的差异就显现出来了，正如之前所说的那样，其它的实现方案都来源于BSD的实现，因此我们首先从BSD说起。

# BSD

## SO_REUSEADDR

如果在绑定一个socket之前设置了`SO_REUSEADDR`，除非两个socket绑定的源地址和端口号都一样，那么这两个绑定都是可行的。也许你会疑惑这跟之前的有什么不一样？**关键是`SO_REUSEADDR`改变了在处理源地址冲突时对通配地址("any ip address")的处理方式**。

当没有设置`SO_REUSEADDR`的时候，socketA先绑定到0.0.0.0:21，然后socketB绑定到192.168.0.1:21的时候将会失败(`EADDRINUSE`错误)，因为0.0.0.0意味着"任意本地IP地址”，也就是"所有本地IP地址“，因此包括192.168.0.1在内的所有IP地址都被认为是已经使用了。但是在设置`SO_REUSEADDR`之后socketB的绑定将会成功，因为0.0.0.0和192.168.0.1事实上不是同一个IP地址，一个是代表所有地址的通配地址，另一个是一个具体的地址。注意上面的表述对于socketA和socketB的绑定顺序是无关的，没有设置`SO_REUSEADDR`，它们将失败，设置了`SO_REUSEADDR`，它将成功。

下面给出了一个表格列出了所有的可能组合：

```
SO_REUSEADDR       socketA        socketB       Result
---------------------------------------------------------------------
  ON/OFF       192.168.0.1:21   192.168.0.1:21    Error (EADDRINUSE)
  ON/OFF       192.168.0.1:21      10.0.0.1:21    OK
  ON/OFF          10.0.0.1:21   192.168.0.1:21    OK
   OFF             0.0.0.0:21   192.168.1.0:21    Error (EADDRINUSE)
   OFF         192.168.1.0:21       0.0.0.0:21    Error (EADDRINUSE)
   ON              0.0.0.0:21   192.168.1.0:21    OK
   ON          192.168.1.0:21       0.0.0.0:21    OK
  ON/OFF           0.0.0.0:21       0.0.0.0:21    Error (EADDRINUSE)
```

上面的表格假定socketA已经成功绑定，然后创建socketB绑定给定地址在是否设置`SO_REUSEADDR`的情况下的结果。Result代表socketB的绑定行为是否会成功。如果第一列是ON/OFF，那么SO_REUSEADDR的值将是无关紧要的。

**现在我们知道`SO_REUSEADDR`对通配地址有影响，但这不是它唯一影响到的方面。还有一个众所周知的影响同时也是大多数人在服务器程序上使用`SO_REUSEADDR`的首要原因**。为了了解其它`SO_REUSEADDR`重要的使用方式，我们需要深入了解TCP协议的工作方式。
      
一个socket有一个发送缓冲区，当调用`send()`函数成功后，这并不意味着所有数据都真正被发送出去了，它只意味着数据都被送到了发送缓冲区中。对于UDP socket来说，如果不是立刻发送的话，数据通常也会很快的发送出去，但对于TCP socket，在数据加入到缓冲区和真正被发送出去之间的时延会相当长。这就导致当我们`close`一个TCP socket的时候，可能在发送缓冲区中保存着等待发送的数据(由于`send()`成功返回，因此你也许认为数据已经被发送了)。如果TCP的实现是立刻关闭socket，那么所有这些数据都会丢失而你的程序根本不可能知道。TCP被称为可靠协议，像这种丢失数据的方式就不那么可靠了。这也是为什么当我们`close`一个TCP socket的时候，如果它仍然有数据等待发送，那么该socket会进入TIME_WAIT状态。这种状态将持续到数据被全部发送或者发生超时。

在内核彻底关闭socket之前等待的总时间(不管是否有数据在发送缓冲区中等待发送)叫做Linger Time。Linger Time在大部分系统上都是一个全局性的配置项而且在默认情况下时间相当长(在大部分系统上是两分钟)。当然对于每个socket我们也可以使用socket选项`SO_LINGER`进行配置，可以将等待时间设置的更长一点儿或更短一点儿甚至禁用它。禁用Linger Time绝对是一个坏主意，虽然优雅的关闭socket是一个稍微复杂的过程并且涉及到来回的发送数据包(以及在数据包丢失后重发它们)，并且这个过程还受到Linger Time的限制。如果禁用Linger Time，socket可能丢失的不仅仅是待发送的数据，而且还会粗暴的关闭socket，在绝大部分情况下，都不应该这样使用。如何优雅的关闭TCP连接的细节不在这里进行讨论，如果你想了解更多，我建议你阅读：[http://www.freesoft.org/CIE/Course/Section4/11.html](http://www.freesoft.org/CIE/Course/Section4/11.html)。而且如果你用`SO_LINGER`禁用了Linger Time,而你的程序在显式的关闭socket之前就终止的话，BSD(其它的系统也有可能)仍然会等待，而不管已经禁用了它。这种情况的一个例子就是你的程序调用了`exit()`(在小的服务器程序很常见)或者进程被信号杀死(也有可能是进程访问了非法内存而终止)。这样的话，不管在什么情况下，你都无法对某一个socket禁用linger了。

问题在于，系统是怎样看待`TIME_WAIT`状态的？如果`SO_REUSEADDR`还没有设置，一个处在`TIME_WAIT`的socket仍然被认为绑定在源地址和端口，任何其它的试图在同样的地址和端口上绑定一个socket行为都会失败直到原来的socket真正的关闭了，这通常需要等待Linger Time的时长。所以不要指望在一个socket关闭后立刻将源地址和端口绑定到新的socket上，在绝大部分情况下，这种行为都会失败。然而，在设置了`SO_REUSEADDR`之后试图这样绑定(绑定相同的地址和端口)仅仅只会被忽略，而且你可以将相同的地址绑定到不同的socket上。**注意当一个socket处于`TIME_WAIT`状态，而你试图将它绑定到相同的地址和端口，这会导致未预料的结果，因为处于`TIME_WAIT`状态的socket仍在"工作"，幸运的是这种情况极少发生**。

对于`SO_REUSEADDR`你需要知道的最后一点是只有在你想绑定的socket开启了地址重用(address reuse)之后上面的才会生效，不过这并不需要检查之前已经绑定或处于`TIME_WAIT`的socket在它们绑定的时候是否也设置这个选项。也就是说，绑定的成功与否只会检查当前`bind`的socket是否开启了这个标志，不会查看其它的socket。

## SO_REUSEPORT

`SO_REUSEPORT`的含义与绝大部分人对`SO_REUSEADDR`的理解一样。基本上说来，`SO_REUSEPORT`允许你将多个socket绑定到相同的地址和端口只要它们在绑定之前都设置了`SO_REUSEPORT`。如果第一个绑定某个地址和端口的socket没有设置`SO_REUSEPORT`，那么其他的socket无论有没有设置`SO_REUSEPORT`都无法绑定到该地址和端口直到第一个socket释放了绑定。

`SO_REUSEPORT`并不表示`SO_REUSEADDR`。这意味着如果一个socket在绑定时没有设置`SO_REUSEPORT`，那么同预期的一样，其它的socket对相同地址和端口的绑定会失败，但是如果绑定相同地址和端口的socket正处在`TIME_WAIT`状态，新的绑定也会失败。当有个socket绑定后处在`TIME_WAIT`状态(释放时)时，为了使得其它socket绑定相同地址和端口能够成功，需要设置`SO_REUSEADDR`或者在这两个socket上都设置`SO_REUSEPORT`。当然，在socket上同时设置`SO_REUSEPORT`和`SO_REUSEADDR`也是可行的。

关于`SO_REUSEPORT`除了它在被添加到系统的时间比`SO_REUSEPORT`晚就没有其它需要说的了，这也是为什么在有些系统的socket实现上你找不到这个选项，因为这些系统的代码都是在这个选项被添加到BSD之前fork了BSD，这样就不能将两个socket绑定到真正相同的“地址” (address+port)。

## Connect() Returning EADDRINUSE?

绝大部分人都知道`bind()`可能失败返回`EADDRINUSE`，然而当你开始使用地址重用(address reuse)，你可能会碰到奇怪的情况:`connect()` 失败返回同样的错误`EADDRINUSE`。怎么会出现这种情况了? 一个远端地址(remote address)毕竟是`connect`添加到socket上的，怎么会已经被使用了? 将多个socket连接到相同的远端地址从来没有出现过这样的情况，这是为什么了？

正如我在开头说过的，一个连接是被一个五元组定义的。同样我也说了任意两个连接的五元组不能完全一样，因为这样的话内核就没办法区分这两个连接了。然而，在地址重用的情况下，你可以把同协议的两个socket绑定到完全相同的源地址和源端口，这意味着五元组中已经有三个元素相同了(协议，源地址，源端口)。如果你尝试将这些socket连接到同样的目的地址和目的端口，你就创建了两个完全相同的连接。这是不行的，至少对TCP不行(UDP实际上没有真实的连接)。如果数据到达这两个连接中的任何一个，那么系统将无法区分数据到底属于谁。因此当源地址和源端口相同时，目的地址或者目的端口必须不同，否则内核无法进行区分，这种情况下，`connect()`将在第二个socket尝试连接时返回`EADDRINUSE`。

## Multicast Address(多播地址)

大部分人都会忽略多播地址的存在，但它们的确存在。单播地址(unicast address)用于单对单通信，多播地址用于单对多通信。大部分人在他们学习了IPv6后才注意到多播地址的存在，但在IPv4中多播地址就有了，尽管它们在公共互联网上用的并不多。

对多播地址来说，`SO_REUSEADDR`的含义发生了改变，因为它允许多个socket绑定到完全一样的多播地址和端口，也就是说，对多播地址`SO_REUSEADDR`的行为与`SO_REUSEPORT`对单播地址完全一样。事实上，对于多播地址，对`SO_REUSEADDR`和`SO_REUSEPORT`的处理完全一样，对所有多播地址，`SO_REUSEADDR`也就意味着`SO_REUSEPORT`。

# FreeBSD/OpenBSD/NetBSD

它们都是很晚的时候衍生自原生BSD的系统，它们与原生BSD的选项和行为都一样。

# MacOS X

MacOS X的内核就是一个BSD类型的UNIX，基于很新的BSD代码，甚至Mac OS 10.3的发布与FreeBSD 5都是同步的，因此MacOS与BSD一样提供相同的选项，处理行为也一样。

# IOS

IOS只是在内核上稍微修改了MacOS，因此选项和处理行为也和MacOS一样。

# Linux

在linux 3.9之前，只存在选项`SO_REUSEADDR`。除了两个重要的差别，大体上与BSD一样。第一个差别：当一个监听(listening)TCP socket绑定到通配地址和一个特定的端口，无论其它的socket或者是所有的socket(包括监听socket)都设置了`SO_REUSEADDR`，其它的TCP socket都无法绑定到相同的端口(BSD中可以)，就更不用说使用一个特定地址了。这个限制并不用在非监听TCP socket上，当一个监听socket绑定到一个特定的地址和端口组合，然后另一个socket绑定到通配地址和相同的端口，这样是可行的。第二个差别: 当把`SO_REUSEADDR`用在UDP socket上时，它的行为与BSD上`SO_REUSEPORT`完全相同，因此两个UDP socket只要都设置了`SO_REUSEADDR`，那么它们可以绑定到相同的地址和端口。

Linux 3.9加入了`SO_REUSEPORT`。这个选项允许多个socket(TCP or UDP)不管是监听socket还是非监听socket只要都在绑定之前都设置了它，那么就可以绑定到完全相同的地址和端口。为了阻止"port 劫持"(Port hijacking)有一个特别的限制：所有希望共享源地址和端口的socket都必须拥有相同的有效用户id(effective user ID)。因此一个用户就不能从另一个用户那里"偷取"端口。另外，内核在处理`SO_REUSEPORT` socket的时候使用了其它系统上没有用到的"特别魔法"：对于UDP socket，内核尝试平均的转发数据报，对于TCP监听socket，内核尝试将新的客户连接请求(由`accept`返回)平均的交给共享同一地址和端口的socket(监听socket)。这意味着在其他系统上socket收到一个数据报或连接请求或多或少是随机的，但是linux尝试优化分配。例如：一个简单的服务器程序的多个实例可以使用`SO_REUSEPORT` socket实现一个简单的负载均衡，因为内核已经把复制的分配都做了。

# Android

尽管整个Android系统与大多数linux发行版都不一样，但是它的内核是个稍加修改的linux内核，因此它的`SO_REUSEADDR`和`SO_REUSEPORT`与linux一样。

# Windows

windows上只有`SO_REUSEADDR`选项，没有`SO_REUSEPORT`。在windows上设置了`SO_REUSEADD`R的socket其行为与BSD上设定了`SO_REUSEPORT`和`SO_REUSEADDR`的行为大致一样，只有一个差别：一个设置了`SO_REUSEADDR`的socket总是可以绑定到已经被绑定过的源地址和源端口，不管之前在这个地址和端口上绑定的socket是否设置了`SO_REUSEADDR`没有。这种行为在某种程度上有些危险因为它允许一个应用程序从别的应用程序上"偷取"已连接的端口。不用说，这对安全性有极大的影响，Microsoft意识到了这个问题，就加入了另一个socket选项: `SO_EXECLUSIVEADDRUSE`。设置了`SO_EXECLUSIVEADDRUSE`的socket确保一旦绑定成功，那么被绑定的源端口和地址就只属于这一个socket，其它的socket不能绑定，甚至他们使用了`SO_REUSEADDR`也没用。

# Solaris

Solaris是SunOS的后羿，SunOS起源于BSD，SunOS 5和之后的版本则基于SVR4，然而SVR4是BSD，System V和Xenix的集合体，所以从某种程度上说，Solaris也是BSD的分支，而且是相当早的一个分支。这就导致了Solaris只有`SO_REUSEADDR`而没有`SO_REUSEPORT`。Solaris上SO_REUSEADDR的行为与BSD的非常相似。从我知道的来看，在Solaris上没办法实现`SO_REUSEPORT`的行为，也就是说，想把两个socket绑定到相同的源地址和端口上是不可能的。

与Windows类似，Solaris也有一个选项提供互斥绑定，这个选项叫`SO_EXCLBIND`。如果在一个socket在绑定之前设置这个选项，那么在其他的socket上设置`SO_REUSEADDR`将没有任何影响。比如socketA绑定了一个通配地址，socketB设置了`SO_REUSEADDR`并且绑定到一个非通配地址和相同的端口，那么这个绑定将成功，除非socketA设置了`SO_EXCLBIND`，在这种情况下，socketB的绑定将失败不管它是否设定了`SO_REUSEADDR`。