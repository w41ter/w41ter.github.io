---
title: Mysql 事务隔离级别的使用
date: 2017-12-7 15:00:00
tags: Mysql
categories: 总结

---

最近在项目中遇到一个问题，在 Mysql 的 Repeatable Read 隔离级别下，出现了数据丢失更新。一开始怀疑的是事务失效，被排查后否定。最后定位到 Mysql 事务的使用问题上。我们的 Sql 场景类似于：

```
SELECT number FROM A WHERE ID = 1;
UPDATE A SET NUMBER = number + 1 WHERE ID = 1;
```

## 事务回顾

事务有四种特性（ACID）：

- 原子性
- 隔离性
- 一致性
- 持久性

在执行事务时可能出现以下问题：

- 丢失更新：
    1. 第一类丢失更新：事务失败回滚时将其他事务已经提交的数据覆盖
    2. 第二类丢失更新：事务提交时，覆盖了其他事务的提交（类似 += ，是不可重复读的特例）
- 脏读：事务读取了其他事务还未提交的内容
- 不可重复读：一个事务中多次读取同一个内容，结果不一致
- 幻读：一个事务中两次查询，但第二次查询比第一次查询多了或少了几行或几列数据

为了解决上述问题，数据库系统提供了四种事务隔离级别供用户选择：

- Read Uncommitted 读未提交：不允许第一类更新丢失。允许脏读，不隔离事务。
- Read Committed 读已提交：不允许脏读，允许不可重复读。
- Repeatable Read 可重复读：不允许不可重复读。但可能出现幻读。
- Serializable 串行化：所有的增删改查串行执行。

在传统的事务隔离级别的实现中，可重复读已经能够避免了两类丢失更新，对于绝大多数的事务，只需要将
隔离级别设置为可重复读。

## Snapshot isolation & MVCC

需要明确的是，以上的ACID和隔离级别定义是在SQL规范层面的定义，不同数据库的实现方式和使用方式并不相同。上面的隔离级别标准是SQL92 基于读写锁的实现方式制定的规范。

为了克服并发问题，各个数据库厂商都引入了 MVCC （多版本并发控制）来提高并发度。所以实际上的事务实现与规范定义的出现了细微的差别，而这细微的差别，就是本文出现的原因。（下文主要以 Mysql innoDB 存储引擎的 MVCC 实现为主，InnoDB 中的 MVCC 为表添加了隐藏的列，打上版本号，来提供多版本功能）。

所以在 MVCC 中，SELECT 语句执行时，会执行快照读取（称为快照读，也称为一致性读）。如果数据被锁，直接读取 undo log 来读取其被锁前的副本。在 Read Commit 隔离级别中，快照读总是读取对应行的最新版本；如果该行被锁住，则会读取最近一次的快照。在 Repeatable Read 隔离级别中，快照读总是读取事务开始时的数据版本。

这种方式极大的提升了并发读取的效率，本质也非常类似乐观锁。所以这种方式实现的隔离级别与规范定义存在一定差异，在 Repeatable Read 中，这种差异导致了 innoDB 第二类更新丢失的出现。因此，使用 MVCC 实现的隔离级别也被称为快照隔离级别。

SI 隔离与规范的 RR 隔离级别的区别在于读取 SI 的 SELECT 语句为快照读，而传统的 SELECT 语句则为当前读（加读锁:locking read, LR）。

在 InnoDB 中，update, delete 执行的是加锁读，想要将 SELECT 语句也设置为加锁读，需要在语句后加上 FOR UPDATE, LOCK IN SHARE MODE。具体的加锁方式取决于用户使用的是那种查询计划：

- unique index with a unique search condition
- a range-type search condition

对于第一种方式，InnoDB 只对其所在的索引进行加锁，不影响其他内容。对于第二种方式，InnoDB 通过使用间隙锁（gap locks)或者 next-key locks 来实现。因为这种加锁落实到区间上，所以也有可能锁住不必要的内容。因此 InnoDB 也号称在 RR 级别上实现了 Serializable 隔离级别。

next-key locks 能排除大多数的幻读现象，只会存在 write skew style 的幻读。

回到题目最开始的问题上，因为这种不规范的事务实现，导致了在高并发情况下会存在第二类丢失更新问题。只需要在 SELECT 后面加上 FOR UPDATE 就能避免出现的问题。

## References

- [事务并发的问题以及其解决方案](http://www.jianshu.com/p/71a79d838443)
- [事务隔离级别与 Mysql 中事务的使用](http://www.fanyilun.me/2015/12/29/%E4%BA%8B%E5%8A%A1%E7%9A%84%E9%9A%94%E7%A6%BB%E7%BA%A7%E5%88%AB%E4%BB%A5%E5%8F%8AMysql%E4%BA%8B%E5%8A%A1%E7%9A%84%E4%BD%BF%E7%94%A8/)
- [Innodb中的事务隔离级别和锁的关系](https://tech.meituan.com/innodb-lock.html)
- [Consistent Nonlocking Reads](https://dev.mysql.com/doc/refman/5.6/en/innodb-consistent-read.html)
- [innodb-transaction-isolation-levels](https://dev.mysql.com/doc/refman/5.6/en/innodb-transaction-isolation-levels.html)