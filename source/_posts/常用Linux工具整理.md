---
title: 常用Linux工具整理
date: 2017-05-03 17:31:54
tags: Linux 
updated: 2017-05-03 20:29:00

---

记录本人常用Linux命令

<!-- more -->

# C

## Cloc

Cloc是一款使用Perl语言开发的开源代码统计工具，支持多平台使用、多语言识别，能够计算指定目标文件或文件夹中的文件数（files）、空白行数（blank）、注释行数（comment）和代码行数（code）。

Cloc具备很多特性以致于让它更方便于使用、完善、拓展和便携。
- 作为一个单一的独立形式存在的文件，Cloc只需要下载相应文件并运行这样最少的安装工作即可。
- 能够从源码文件中识别编程语言注释定义；
- 允许通过语言和项目来分开统计计算；
- 能够以纯文本、SQL、XML、YAML、逗号分隔等多样化的格式生成统计结果；
- 能够统计诸如tar、Zip等格式的压缩文件中的代码数；
- 有许多排除式的指令；
- 能够使用空格或者不常用的字符处理文件名和目录名；
- 不需要依赖外部标准的Perl语言配置；
- 支持多平台使用。

```
Usage: cloc [options] <file(s)/dir(s)> | <set 1> <set 2> | <report files>
```



### Usage

// TODO: 

# G

## GDB

### 开始和停止

`quit`: 退出GDB
`run`: 运行程序（在此给出命令行参数）
`kill`: 停止程序

### 断点

`break sum`: 在函数 sum 入口设置断点
`break *0x8048394`: 在地址 0x8048394 处设置断点
`delete 1`: 删除断点1
`delete`: 删除所有断点

### 执行

`stepi`: 执行一条指令
`stepi 4`: 执行四条指令
`nexti`: 类似`stepi`，但是以函数调用为单位
`continue`: 继续执行
`finish`: 运行到当前函数返回

### 检查代码

`disas`: 反汇编当前函数
`disas sum`: 反汇编函数`sum`
`disas 0x000001`: 反汇编位于地址 0x000001 附近的函数
`disas 0x000000 0x000001`: 反汇编指定范围的代码
`print /x $eip`: 以十六进制输出程序计数器的内容

### 检查数据

`print $eax`: 以十进制数出 $eax 的内容
`print /x $eax`: 以十六进制输出
`print /t $eax`: 以二进制输出
`print sum`: 输出sum的值
`print *(int*)sum`: 输出sum指向int的值
`x/20b sum`: 检查函数sum的前20个字节
`x/2w 0xfff076b0`: 检查0xfff076b0开始的4字节

### 有用的信息

`info frame`: 有关与当前栈帧的信息
`info registers`: 所有寄存器的值
`help`: 显示GDB的帮助信息

# O

## Objdump

### info 
 
Display infomation from object files.

```
#include <stdio.h>

int main(void) {
  printf("hello world");
  return 0;
}
```

使用`gcc hello.c`生成`hello.o`文件，下面使用`hello.o`作为源文件使用objdump。

### usage

`-f, --file-headers` 显示整个文件头部的内容

```
/mnt/d/tmp$ objdump -f hello.o

hello.o:     file format elf64-x86-64
architecture: i386:x86-64, flags 0x00000011:
HAS_RELOC, HAS_SYMS
start address 0x0000000000000000

```

`-h, --[section]-headers` 显示文件的`section`头信息

```
/mnt/d/tmp$ objdump -h hello.o

hello.o:     file format elf64-x86-64

Sections:
Idx Name          Size      VMA               LMA               File off  Algn
  0 .text         0000001a  0000000000000000  0000000000000000  00000040  2**0
                  CONTENTS, ALLOC, LOAD, RELOC, READONLY, CODE
  1 .data         00000000  0000000000000000  0000000000000000  0000005a  2**0
                  CONTENTS, ALLOC, LOAD, DATA
  2 .bss          00000000  0000000000000000  0000000000000000  0000005a  2**0
                  ALLOC
  3 .rodata       0000000c  0000000000000000  0000000000000000  0000005a  2**0
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  4 .comment      00000035  0000000000000000  0000000000000000  00000066  2**0
                  CONTENTS, READONLY
  5 .note.GNU-stack 00000000  0000000000000000  0000000000000000  0000009b  2**0
                  CONTENTS, READONLY
  6 .eh_frame     00000038  0000000000000000  0000000000000000  000000a0  2**3
                  CONTENTS, ALLOC, LOAD, RELOC, READONLY, DATA
```

Idx 是编号，Name 是节点名称，Size 是节大小，VMA 是在虚拟内存中的起点，LMA 是节的装载地址（除了ROM之外，通常与 VMA 相同），File off 是在文件中的具体偏移，Algn 是对齐地址。各节第二行描述了节的属性。CONTENTS 表示节在文件中占用了内存空间，ALLOC 则表示需要分配内存，RELOC 表示需要重定位。

`-d, --disassemble` 显示可执行`section`的反汇编代码

```
/mnt/d/tmp$ objdump --disassemble hello.o

hello.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <main>:
   0:   55                      push   %rbp
   1:   48 89 e5                mov    %rsp,%rbp
   4:   bf 00 00 00 00          mov    $0x0,%edi
   9:   b8 00 00 00 00          mov    $0x0,%eax
   e:   e8 00 00 00 00          callq  13 <main+0x13>
  13:   b8 00 00 00 00          mov    $0x0,%eax
  18:   5d                      pop    %rbp
  19:   c3                      retq
```

`-D, --disassemble-all` 显示所有`section`的反汇编

NOTICE: **反汇编过程中使用 `-M` 可以设置反汇编格式：**

```
(multiple options should be separated by commas):
  x86-64      Disassemble in 64bit mode
  i386        Disassemble in 32bit mode
  i8086       Disassemble in 16bit mode
  att         Display instruction in AT&T syntax
  intel       Display instruction in Intel syntax
  att-mnemonic
              Display instruction in AT&T mnemonic
  intel-mnemonic
              Display instruction in Intel mnemonic
  addr64      Assume 64bit address size
  addr32      Assume 32bit address size
  addr16      Assume 16bit address size
  data32      Assume 32bit data size
  data16      Assume 16bit data size
  suffix      Always display instruction suffix in AT&T syntax
  amd64       Display instruction in AMD64 ISA
  intel64     Display instruction in Intel64 ISA
```

比如要显示 Intel 格式的汇编代码：

```
/mnt/d/tmp$ objdump --disassemble -M intel hello.o

hello.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <main>:
   0:   55                      push   rbp
   1:   48 89 e5                mov    rbp,rsp
   4:   bf 00 00 00 00          mov    edi,0x0
   9:   b8 00 00 00 00          mov    eax,0x0
   e:   e8 00 00 00 00          call   13 <main+0x13>
  13:   b8 00 00 00 00          mov    eax,0x0
  18:   5d                      pop    rbp
  19:   c3                      ret
```

`-t, --syms` 显示符号表内容

```
/mnt/d/tmp$ objdump -t hello.o

hello.o:     file format elf64-x86-64

SYMBOL TABLE:
0000000000000000 l    df *ABS*  0000000000000000 hello.c
0000000000000000 l    d  .text  0000000000000000 .text
0000000000000000 l    d  .data  0000000000000000 .data
0000000000000000 l    d  .bss   0000000000000000 .bss
0000000000000000 l    d  .rodata        0000000000000000 .rodata
0000000000000000 l    d  .note.GNU-stack        0000000000000000 .note.GNU-stack
0000000000000000 l    d  .eh_frame      0000000000000000 .eh_frame
0000000000000000 l    d  .comment       0000000000000000 .comment
0000000000000000 g     F .text  000000000000001a main
0000000000000000         *UND*  0000000000000000 printf
```

各列分别是界内偏移，标记位，所在节，对齐方式和符号名。`*ABS*` 表示这是一个不和任何节相关的绝对符号，`*UND*`则这个符号不在本文件中定义，`*COM*` 表示还未分配位置的未初始化数据目标。

`-T, --dynamic-syms` 显示文件的动态符号表入口,仅仅对动态目标文件有意义，比如共享库。

`-r, --reloc` 显示重定位入口

```
:/mnt/d/tmp$ objdump -r hello.o

hello.o:     file format elf64-x86-64

RELOCATION RECORDS FOR [.text]:
OFFSET           TYPE              VALUE
0000000000000005 R_X86_64_32       .rodata
000000000000000f R_X86_64_PC32     printf-0x0000000000000004


RELOCATION RECORDS FOR [.eh_frame]:
OFFSET           TYPE              VALUE
0000000000000020 R_X86_64_PC32     .text
```

分别表示 text 和 eh_frame 节的重定位表。所谓重定位表是指代码中需要回填地址的表，链接器重定位算法大概如下：

```
foreach section s {
  foreach relocation entry r {
    refptr = s + r.offset;
    if (r.type == XXXX_PC32) {
      refaddr = ADDR(s) + r.offset;
      *refptr = ADDR(r.symbol) + *refptr - refaddr;
    }
    if (r.type == XXXX_32) {
      *refptr = ADDR(r.symbol) + *refptr;
    }
  }
}
```

如果配合`d D`使用,则以反汇编以后的格式显示:

```
/mnt/d/tmp$ objdump -rd hello.o

hello.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <main>:
   0:   55                      push   %rbp
   1:   48 89 e5                mov    %rsp,%rbp
   4:   bf 00 00 00 00          mov    $0x0,%edi
                        5: R_X86_64_32  .rodata
   9:   b8 00 00 00 00          mov    $0x0,%eax
   e:   e8 00 00 00 00          callq  13 <main+0x13>
                        f: R_X86_64_PC32        printf-0x4
  13:   b8 00 00 00 00          mov    $0x0,%eax
  18:   5d                      pop    %rbp
  19:   c3                      retq
```

`-R, --dynamic-reloc` 显示动态重定位入口，仅仅对动态文件起作用。

# T

## time


来自: [Linux Man 手册](http://man.linuxde.net/time)
time命令用于统计给定命令所花费的总时间。 

### 语法 

```
time 参数 
```

### 参数 
指令：指定需要运行的额指令及其参数。 
实例 当测试一个程序或比较不同算法时，执行时间是非常重要的，一个好的算法应该是用时最短的。所有类UNIX系统都包含time命令，使用这个命令可以统计时间消耗。例如： 

```
[root@localhost ~]# time ls 
anaconda-ks.cfg install.log install.log.syslog satools text 

real 0m0.009s 
user 0m0.002s 
sys 0m0.007s 
```

输出的信息分别显示了该命令所花费的real时间、user时间和sys时间。 

real时间是指挂钟时间，也就是命令开始执行到结束的时间。这个短时间包括其他进程所占用的时间片，和进程被阻塞时所花费的时间。 

user时间是指进程花费在用户模式中的CPU时间，这是唯一真正用于执行进程所花费的时间，其他进程和花费阻塞状态中的时间没有计算在内。 sys时间是指花费在内核模式中的CPU时间，代表在内核中执系统调用所花费的时间，这也是真正由进程使用的CPU时间。 

shell内建也有一个time命令，当运行time时候是调用的系统内建命令，应为系统内建的功能有限，所以需要时间其他功能需要使用time命令可执行二进制文件/usr/bin/time。 

使用-o选项将执行时间写入到文件中： 

```
/usr/bin/time -o outfile.txt ls 
```

使用-a选项追加信息： 

```
/usr/bin/time -a -o outfile.txt ls 
```

使用-f选项格式化时间输出： 

```
/usr/bin/time -f "time: %U" ls 
```

-f选项后的参数： 
参数	描述 
%E	real时间，显示格式为[小时:]分钟:秒 
%U	user时间。 
%S	sys时间。 
%C	进行计时的命令名称和命令行参数。 
%D	进程非共享数据区域，以KB为单位。 
%x	命令退出状态。 
%k	进程接收到的信号数量。 
%w	进程被交换出主存的次数。 
%Z	系统的页面大小，这是一个系统常量，不用系统中常量值也不同。
%P	进程所获取的CPU时间百分百，这个值等于user+system时间除以总共的运行时间。 
%K	进程的平均总内存使用量（data+stack+text），单位是KB。 
%w	进程主动进行上下文切换的次数，例如等待I/O操作完成。 
%c	进程被迫进行上下文切换的次数（由于时间片到期）。

# 系统

## Ubuntu

### 软件安装

#### APT 安装

普通安装：`apt install softname1 softname2 ...`
修复安装: `apt -f install softname1 softname2 ...`
重新安装: `apt --reinstall install ....`

#### DPKG 安装

`dpkg -i package_name.deb`

#### 源码安装

通过tar解压，然后configure后make install

tar: `tar method filename`

.tar.gz, .tar.Z, .tgz: `zxf`
.tar: `xf`

.bz2: `bunzip xx.bz2`

### 卸载

#### APT方式

移除式卸载：`apt-get remove softname1 softname2 …`;（移除软件包，当包尾部有+时，意为安装）

清除式卸载 ：`apt-get --purge remove softname1 softname2...`;(同时清除配置)

清除式卸载：`apt-get purge sofname1 softname2...`;(同上，也清除配置文件)

#### Dpkg方式

移除式卸载：`dpkg -r pkg1 pkg2 ...`;

清除式卸载：`dpkg -P pkg1 pkg2...`;