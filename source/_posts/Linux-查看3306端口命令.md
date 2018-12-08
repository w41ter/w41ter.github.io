---
title: Linux 查看3306端口命令
date: 2017-02-23 17:12:18
tags: 
    - Linux 
    - Mysql 

---

- 查看3306端口被什么程序占用 `lsof -i :3306`

- 查看3306端口是被哪个服务使用着 `netstat -tunlp | grep :3306`

- 查看3306端口的是否已在使用中，可验证使用该端口的服务是否已正常运行 `netstat -an | grep :3306`