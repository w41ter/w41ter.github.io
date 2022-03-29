---
title: Jenkins + Docker + Git 搭建持续继承、自动部署平台
date: 2017-11-04 08:47:17
tags:
categories: 总结

---

## 安装依赖

## 安装 Docker 

Ubuntu 安装 Docker 非常方便:

```
sudo apt update
sudo apt install docker.io
```

安装好后使用 `docker --version` 看到:

```
$ docker --version
Docker version 1.13.1, build 092cba3
```

此时安装成功。为了方便使用 docker 仓库，需要使用 [Docker 提供的镜像加速](https://www.docker-cn.com/registry-mirror):

```
$ sudo vim /etc/docker/daemon.json
```

添加内容如下：

```
{
  "registry-mirrors": ["https://registry.docker-cn.com"]
}
```

修改了镜像源后需要重启 Docker daemon 服务:

```
$ sudo service docker restart
```

所以可以使用如下命令判断 docker 服务是否在线：

```
$ sudo service docker start
 * Starting Docker: docker                                          [ OK ]
```

关于 docker 使用参考[Docker 入门教程](http://dockone.io/article/111)。

## Jenkins 安装

jenkins 有多种安装办法，其中就包括一个 docker Image。可以直接使用 docker 安装：

```
docker pull jenkins:latest
```

`pull` 表示从远程拉取一个 image，名称为 `jenkins`，`lastest` 表示使用最新版本。

接下来可以运行 jenkins 容器：

```
docker run -t -p 8080:8080 -p 8083:8083 -p 50000:50000  -v /var/jenkins_home:/var/jenkins_home jenkins:latest
```

这种方式启动会存储数据，`-t` 表示以后台模式运行，`-p`标示容器和宿主服务器之间的开放端口号，`-v`表示需要将本地哪个目录挂载到容器中，格式：`-v <宿主机目录>:<容器目录>`。

# Refereces

- [在Ubuntu 14.04安装和使用Docker](http://blog.csdn.net/chszs/article/details/47122005)
