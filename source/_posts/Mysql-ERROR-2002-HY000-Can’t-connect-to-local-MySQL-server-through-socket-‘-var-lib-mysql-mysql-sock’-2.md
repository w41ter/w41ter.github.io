---
title: >-
  Mysql ERROR 2002 (HY000): Can’t connect to local MySQL server through socket
  ‘/var/lib/mysql/mysql.sock’ (2)
date: 2017-02-23 17:15:06
tags: 
  - Mysql
  - Linux

---

使用 `mysql -uroot -p` 连接 Mysql 时出现了下面的错误:

```
ERROR 2002 (HY000): Can’t connect to local MySQL server through socket
  ‘/var/run/mysqld/mysqld.sock’ (2)
```

经过排查，发现是权限问题，使用:

```
chown -R mysql:mysql /var/run/mysqld
```

修改权限，然后启动，成功。