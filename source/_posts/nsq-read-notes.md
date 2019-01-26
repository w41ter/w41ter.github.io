---
title: nsq read notes
date: 2019-01-3 8:00
tags: 
	- Nsq
    - MessageQueue
categories: 消息中间件
mathjax: true
---

# nsqd

```go
topicMap map[string]*Topic
clientMap map[id]*Client
```

## 初始化过程

1. new
2. load meta data
3. persist meta data
4. main
	1. listen tcp & http port, start server
	2. start queueScanLoop, lookupLoop, statsLoop

有新连接到达时，会生成 connection 的 client，保存到 nsqd 的 clientMap 中，同时启动 goroutine 负责 client 的 messagePump。conn 所在的 goroutine 之后会负责读客户端的命令，并执行以及返回结果。可执行命令如下：

1. IDENTIFY: 表名身份
2. FIN: 在 client 绑定的 channel 上，完成一条消息（调用 channel.FinishMessage），同时会更新当前 client 的 metrics 信息，以及状态
3. RDY: 更新 client ready count
4. REQ: 在 client 绑定的 channel 上，把一条消息重新送入队列（调用 channel.RequeueMessage），同时更新 metrics 和状态。这条消息会被放入 defered 队列，延后执行
5. PUB: 往某个 client 有权限的 topic 发送一条消息（调用 topic.PutMessage），更新 metrics 状态
6. MPUB: 和 PUB 一样，不过接收多条消息
7. DPUB: 和 PUB 一样，不过会被放入 defered 队列
8. NOP: 最简单，啥也不干
9. TOUCH: 在 client 绑定的 channel 上，重置一条消息的过期时间（调用 channel.TouchMessage)
10. SUB: 将 client 绑定到 channel 上，如果 topic 和 channel 任一个属于 "", 且 topic 或 channel 正在关闭， client 会不断重试绑定操作。
11. CLS: 关闭连接
12. AUTH: 授权

client 有多种状态：init, disconnect, connect, subscribe, closing ，状态迁移由一系列命令执行顺序决定。除此外还有 ready 状态，client 通过 RDY 更新了自己的 ready count，表示 client 最多同时处理多少条消息，如果 inflight count >= ready count，则未 ready，需要等待。

client 使用 SUB 进入 subscribe 模式，该模式只能进入一次，进入后 messagePumb 会接收到 subEvent，然后从对应 channel 中读取 message 发送到 client 里。

## topic

```go
messageChan chan *Message
backendChan BackendChan
channelsMap map[string]Channels
```

### topic 创建流程

1. new topic, save to topicMap
2. lookup each lookupd, get all channels in topic $TOPIC
3. skip "#ephemeral" and create channels
4. start topic messagePump

### delete channel

1. remove from topic channelsMap
2. mark channel deleted
3. if left channels is zero, and topic is ephemeral, delete topic self

### put messages

1. try put message into memory message channel
2. fallthrough into backend queue, most case into disk, but ephemeral just ignore
3. update message count

### message pump

1. read message from memory message channel
2. else read from backend message
3. else update channel status
4. copy memory into each channels in current topic
	1. if message is defered, put into channels defered
	2. else put into normal channels

## channel

```go
clients map[string]Consumer
backend BackendQueue
memoryChan chan *Message
deferedMessages map[MessageID]*Message
defredPQ PriorityQueue
inFlightMessages map[MessageID]*Message
inFlightPQ PriorityQueue
```

channel put message 和 topic put message 类似。put defered message 会把 message 放在deferedMessages 中，并加入 deferedPQ 中。如果 defered 时间到了，使用正常流程 put。clients 提供了 Add 和 Remove 接口，但管理职责不是 channel 的。

# nsqlookupd

## nsqlookupd 数据组织方式

```go
{
	{"client", "", ""} => {
		"127.0.0.1:9490" => Producer{"127.0.0.1:8081"},
		"127.0.0.1:9491" => Producer{"127.0.0.1:8081"},
	},

	{"channel", "topic_a", "channel_a"} => {
		"ip1" => Producer{"addr"},
	},
	{"topic", "topic_a", ""} => {
		"ip1" => Producer{"addr_1"},
		"ip2" => Producer{"addr2"},
	},
}
```

## nsqd <-> nsqlookupd 交互

1. connect: send "  V1"
2. ping: send "PING "
	1. nsqlookupd update peer info's lastUpdate
	2. response "OK"
3. identify: send "IDENTIFY LEN(data) data"
	1. remote addr as id
	2. load broadcase address, tcp port, http port, version
	3. update peer info's lastUpdate
	4. add producer to db: Registration{"client"} => PeerInfo{id}
	5. response {tcp_port, http_port, version, hostname, broadcast_address}
4. register: send "REGISTER TOPIC [CHANNEL]"
	1. read topic and channel name
	2. if channel name exists:
		1. add producer to db: Registration{"channel", $TOPIC, $CHANNEL} => PeerInfo{id}
	3. add producer to db: Registration{"topic", $TOPIC, ""} => PeerInfo{id}
	4. response "OK"
5. unregister: send "UNREGISTER TOPIC [CHANNEL]"
	1. read topic and channel name
	2. if channel name exists:
		1. remove producer from db: Registration{"channel", $TOPIC, $CHANNEL}
		2. remove registration for channel has suffix "#ephemeral" if left producer is zero
	3. else:
		1. find all registrations of channel of $TOPIC
		2. remove all channels of current peer
		3. remove producer form db: Registration{"topic", $TOPIC, ""}
	4. response "OK"

## nsqlookupd support http request

1. GET /lookup?topic=topic_name
```json
{
	"channels": ["channel1"],
	"producers": [{

	}],
}
```
1. GET /topics
2. GET /channels?topic=topic_name
3. GET /nodes
4. POST /topic/create?topic=
5. POST /topic/delete?topic=
6. POST /channel/create?topic=topic&channel=channel
7. POST /channel/delete?topic=&channel=
8. POST /topic/tombstone?topic=topic_name&node=node_id
