---
layout: post
title: 'Mysql The server quit without updating PID file (/var/run/mysqld/mysqld.pid) '
date: 2017-02-23 17:06:37
tags: Mysql

---

Mysql 启动时出现以下错误:

```
The server quit without updating PID file (/var/run/mysqld/mysqld.pid)
```

根据网上方法，用: `sudo find / -name my.conf` 发现有多个 `my.conf` 文件存在:

```
/var/my.conf
/var/mysql/my.conf
```

删除 `/etc/mysql/my.cnf` 这个文件，启动MySql服务，成功。