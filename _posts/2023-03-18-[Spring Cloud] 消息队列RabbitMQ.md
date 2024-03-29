---
layout:     post
title:      "[Spring Cloud] 消息队列与RabbitMQ"
subtitle:   "消息队列概念与RabbitMQ知识点"
author:     Penistrong
date:       2023-03-18 17:38:30 +0800
categories: java spring
catalog:    true
mathjax:    false
katex:      true
tags:
    - Java
    - MQ
    - Spring
    - Spring Cloud
---

# 消息队列

## 架构设计

### 什么是消息队列？

消息队列就是一个FIFO的存放消息的容器，当需要使用消息时就从队列里取出消息，按顺序对消息进行消费

参与消息传递的双方称为生产者和消费者(经典的生产消费设计模式)，生产者负责发送消息，消费者负责处理消息

随着分布式和微服务的发展，消息队列在系统设计中有了更大的发挥空间，其应用场景广阔，是分布式和微服务系统的重要组件之一

## 应用场景

> 消息驱动是通过"削峰填谷"解决高并发场景

消息驱动场景有很多种，下面有4种经典场景

### 服务间解耦

如果没有消息队列，那么微服务之间仍然存在上下游间的直接调用关系，类似于耦合的业务场景，比如某个上游微服务通过某个事件触发了多个下游业务，这类场景就需要消息驱动技术进行解耦合

消息队列可以收纳业务场景里某个微服务下的业务发送出的消息，与其关联的下游服务通过监听这个队列进行处理，而不是直接受上游业务调用，对扩展性也很适配，下游服务添加新场景时对上游服务是无感知的，因为他们只需要对接消息队列，并不需要直接对上游业务发起回应调用

从设计模式的角度而言，这就像**生产者-消费者**模式，消息队列储存生产者业务生产出的消息，与其相关的消费者业务对队列中的消息执行消费

### 消息广播

消息广播可以让消费者组里所有的消费者对某个消息都做一次消费

消息广播的常用场景就是处理热点数据，比如说突发的明星塌方，成为一条“热点数据”，肯定需要通知所有服务防范热点数据的洪流。这种场景就非常适合使用消息广播，侦测到热点数据时发送一个消息到特定的消息队列里，让所有有可能接收到热点请求的应用服务接入这个队列，监听到后就可以及时执行热点逻辑

### 延迟业务

有部分任务是需要延迟的，它门会在未来的某个时间被执行，比如经典电商场景里的:

- 自动确认收货: 顾客签收商品后迟迟不确认收货，到达一定时间阈值后系统会自动确认

- 自动取消未支付订单: 下单后迟迟没有完成支付，30分钟后自动取消该订单

这些延迟业务都以通过延迟消息来实现，当然这种延迟的消息有可能会积压很多，还会需要消息分区等功能降低消息积压量

### 削峰填谷

- 削峰：削减峰值流量，当某个业务峰值流量超过系统吞吐量上限，而这类业务又是核心业务，不能简单粗暴地使用限流、降级、熔断等方式直接杀掉请求，可以使用消息队列收纳这些请求，让下游消费者业务根据自身的吞吐量从队列中获取这些消息进行消费

- 填谷: 峰值流量降低后，前面削峰阶段积压在消息队列里的请求就可以被下游消费者慢慢消化

削峰填谷就是一种平滑利用资源的手段，适用于实时性要求不高但并发量较高的业务，比如新店家入驻电商平台，需要将他们准备好的商品元数据一次性注册到商品中心、商品发布主图副图、营销优惠活动页面、详情页等等，这些请求其实实时性并不高，但是由于商品元数据极多，很容易达成流量洪峰冲击，使用消息队列就可以进行削峰填谷

## 相关问答

### 业务设计: 订单超时未支付自动取消

> **Q**: 淘宝、京东等电商在你购买商品时会提交一个订单，如果客户没有付款，那么通常这个订单会在限定时间内被取消，如何使用消息队列解决该业务场景?

京东面试官告诉我，对于这种场景题，要从多方面考虑，比如：提交的订单是否要持久化到数据库？超过支付时间后是否要实时通知用户？从多方面考虑，才能满足面试官的用意“考察你的发散思维能力”

**A**:

1. 定时任务关闭订单：定时任务的扫描间隔犹如一个窗口，如果刚扫描完成就有一个订单被提交且其超时时间与扫描窗口长度一致，那么他要一直等到两个窗口后才能确定是否被取消，且频繁扫描主订单号会带来网络与磁盘IO消耗，不推荐

2. 消息队列延迟业务：如果是RocketMQ可以设定消息的延迟时间(但是开源版本固定为18个级别，只有商业版本可以任意指定时间)，对于RabbitMQ其本体原生不具备延迟消息功能

   - 一种曲线救国方式：向正常消息队列中添加一个具有TTL超时时间的消息，当客户一直没有付款，超过TTL后，该订单消息就被DLX（死信交换机）存入死信队列里，服务只需从死信队列中取出订单消息，就可以取消该订单。

   - 使用消息队列插件，比如RabbitMQ的延迟消息交换机插件`rabbitmq_delayed_message_exchange`

3. 时间轮算法：利用时间轮算法，每出现一个订单就根据该订单的超时时间计算其需要被放置的slot位置，将`Cycle Number`(时间轮圈数)和订单号组成一个Task存入slot的`Set`中。时间轮按照设置好的精度不断移动(比如设置为1秒时，每秒都移动1个slot)，当扫描slot-`Set`里有`Cycle Number = 0`的任务，则取出该任务对应的订单号，另开一个线程执行订单超时关闭的业务逻辑

4. Redis过期监听

   - `redis.conf`设置`notify-keyspace-events Ex`，开启键过期的通知事件

   - redis利用定期删除+惰性删除对过期字典里过期的键执行删除，而定期删除是每100ms**随机抽取**过期的key进行删除，惰性删除是只有下一次访问该key发现过期才进行删除。这两种删除策略都会导致订单超时处理场景下，不能保证到点精准删除过期键，造成延时，且Redis删除过期键后发送过期通知时，如果对应的应用重启，那么通知事件就会丢失导致订单一直无法被关闭

5. 定时任务分布式批处理：通过定时任务不停轮询数据库的订单，将已经超时的订单捞出来，分发给不同的机器分布式处理

   - 前面第一种就说了，定时任务的精度不高，轮询频率过高导致数据库QPS较大进而影响其他线上业务

   - 抽离出超时中心+超时库单独做订单的超时调度，超时中心包含多个分布式节点，从超时库取出超时订单后交由超时中心不同的节点进行处理，并通知交易履约服务写入真正的订单库中

   - 利用任务调度系统比如SchedulerX，让超时中心的不同节点协同工作并拉取不同数据进行处理

### 消息队列的相关区别问题

1. > **Q**：RPC和消息队列的区别？RPC即**R**emote **P**rocedure **C**all，远程过程调用

   **A**:
   - 从用途上看：RPC主要解决服务之间的远程通信问题，使用RPC可以调用远程计算机上某个服务提供的方法，就像调用本地方法一样，面向过程；消息队列更多用于服务解耦、异步任务、消息广播、削峰填谷这些应用场景

   - 从通信方式上看：RPC是服务之间的双向直接通讯，而消息队列本身是作为中转站，服务间通过消息队列这个中间载体进行间接的网络通讯

   - 从架构上看: RPC是直接发起调用获取返回值，而消息队列需要将消息存储在自己内部，还可能需要主从模式甚至分布式集群

   - 从时效性上看：RPC发出的调用通常会立即被远端服务处理，而消息队列中存放的消息可以延迟以达成异步处理的效果

2. > **Q**：JMS和AMQP有什么区别？

   **A**:
   - JMS(**J**ava **M**essage **S**ervice, Java消息服务)是Java API提供的消息服务，但是对于跨平台支持较差。JMS支持两种消息模型：1.点对点P2P模型，一条消息只能被一个消费者使用 2.发布订阅模型，使用Topic作为消息通信载体，类似于消息广播模式，订阅了该Topic的消费者可以收到同一topic下的广播消息

   - AMQP(**A**dvanced **M**essage **Q**ueuing **P**rotocol，高级消息队列协议)，是应用层协议的一个开放标准，专门为面向消息的中间件设计，且兼容JMS。基于AMQP的消息中间件与客户端之间传递消息并不受跨平台、跨语言的限制，因为AMQP的消息类型为二进制byte[]字节数组，例如Java就可以序列化对象后发送消息或者接收消息后再反序列化。

     1. AMQP内部增加了交换机exchange的概念，其消息模型除了direct exchange仍属于点对点消费之外，其余四种(fanout、topic、system、headers)都是在发布订阅模型基于交换机的路由能力细分的消费模型

     2. AMQP协议有三层：

        - Module Layer: 协议最高层，定义客户端调用命令
        - Session Layer: 中间层，负责发送客户端命令到服务器，再将服务端应答返还给客户端，提供可靠性同步机制和错误处理
        - Transport Layer: 最底层，传输二进制数据流，提供信道复用、帧处理、错误检测等功能

     3. AMQP三大组件：交换机Exchange、队列Queue、绑定Binding

## RabbitMQ

RabbitMQ基于Erlang语言实现AMQP协议，它与其他消息队列竞品具有以下不同

- 吞吐量: 比RocketMQ和Kafka低一个数量级

- 可用性：RabbitMQ基于主从架构实现高可用，而RocketMQ和Kafka基于分布式架构，一个数据在不同节点上有多个副本

- 时效性/并发性：基于Erlang开发的RabbitMQ并发能力非常强，延时为微妙级，而其他竞品都是毫秒级

### 架构

RabbitMQ整体架构为，生产者生产的消息发到交换机，交换机再根据消息头单播或广播到不同队列中，而消费者只需要监听队列即可获取消息

#### 生产者和消费者

生产者和消费者分别负责生产消息和消费消息，消息由两部分组成：

- 消息头(标签 Label): 由一系列**可选**属性构成，包括routing-key(路由键)、priority(相较于其他消息的优先权)、delivery-mode(是否需要持久化)等，RabbitMQ会根据消息头转发对应消息

- 消息体(PayLoad): 不透明的Byte[]数组，只有对应的消费者知道该如何消费

#### 交换机 Exchange

RabbitMQ中的消息再进入Queue之前必须还要经过Exchange

交换机会根据消息头里的Routing Key属性指定的路由规则，与当前交换机类型和Binding Key(绑定键)联合使用，最终路由到对应的Queue之中，如果路由不到可能会返还给生产者(设置mandaory参数)，或者直接被丢弃掉

RabbitMQ内部通过Binding(绑定)将交换机Exchange和消息队列Queue关联起来，一个绑定就是基于Routing Key将交换机和消息队列连接起来的路由规则，交换器就像是一个装满了绑定规则的路由表。Exchange和Queue的绑定可以是多对多的。

交换机有四种类型，对应不同路由策略

1. fanout: 正如其名，像风扇出风口一般快速发送消息，它会将发送到该交换机的消息路由到**所有**与它绑定的Queue中，不需要判断Routing Key和Binding Key，速度最快，常用来广播消息

2. direct: 将消息路由到Routing Key与Binding Key完全匹配的队列里，如果多个队列的Binding Key相同，那么都会发送

3. topic: 严格匹配方式不一定能满足大部分业务场景，需要模糊匹配或者前缀匹配的时候就轮到topic交换机发挥作用了。它的匹配规则为:

   - Routing Key为一个由点号"."分隔的字符串，分隔开的每一段子字符串称为单词
   - Binding Key也是如此，但是存在通配符"\*"和"#"，其中"\*"用于匹配一个单词，"#"用于匹配0~N个单词

4. headers: 这种类型的交换机不依赖于Routing Key，而是根据消息头(headers)里设置的其他属性(键值对)，如果其中包含了该交换机和消息队列绑定时指定的键值对，则将消息路由到这些队列消息队列中，性能较差

#### 队列 Queue

Queue会一直保存消息，直到订阅它的消费者连接到该队列后将消息取出消费。多个消费者可以订阅同一个队列(可以理解为一个服务集群下的不同实例都订阅了该消息队列)，该队列里的消息会根据Round-Robin轮询策略发送给不同消费者处理，而不是每个消费者都收到消息的副本，避免重复消费问题

这就意味着，不支持**队列层面**的消息广播，如果有广播消息的需求，建议让服务实例监听不同的通知队列，相应的广播消息应该在交换机层面就广播到这些队列中

### RabbitMQ如何传输消息？

由于TCP资源开销较大，所以RabbitMQ是基于信道的方式来传输数据，一条TCP链接上建立大量信道，每个信道都有唯一ID保证私有性，每个线程对应一个信道，相当于多个线程共享一个TCP链接，并在其中的信道上传输数据

### 消费者与消息队列间是推模式还是拉模式?

当谈到消息队列的推拉模式时，一般都是指消费者Consumer和消息队列Broker之间的交互方式，下面讨论的主要也是Consumer和Broker之间的推拉模式

> 生产者Producer和消息队列Broker之间默认是推模式，由生产者推送消息，而不是Broker主动拉取，保证消息的实时性

#### 推模式

**定义**: 消息由Broker推向Consumer，即Consumer被动地接收消息，由Broker主导消息的发送

**优点**: 推模式的消息实时性较高，Broker接收完消息后马上推送给Consumer，对于消费者来说十分简单只需要被动等待消息被推送过来后自己再进行处理

**缺点**:

1. **推送速率难以匹配消费速率**: 在推模式下，Broker一有消息就进行推送(虽然可以通过设置QPS速率限制推送速度)，但是Broker的发送速率和Consumer的消费速率难以匹配，如果超过了消费速率而一直推送消息会导致消费者那边直接爆仓，无法处理

2. **不同消费者的消费速率不一样**: Broker主动推消息的情况下，由于不同消费者的消费速率不一致，就算让消费者与Broker沟通自适应推送速率，但是Broker需要主动维护每个消费者的状态并对推送速率进行更新，无疑增加了Broker自身的复杂度

**适用场景**: 推模式难以根据消费者的状态控制推送速率，适用于消息量不大、消息实时性高、消费者消费能力较强的场景

#### 拉模式

**定义**: 消息由Consumer主动向Broker请求拉取，即Broker被动地发送消息，由Consumer主导消息的拉取

**优点**:

1. 拉模式下，主动权在Consumer这里，消费者可以根据自身的情况发起拉取消息的请求，一旦消费者面临一定的消费压力时，可以主动停止拉取、或者过段时间再进行拉取，灵活性较高

2. Broker更加轻松，只需要负责路由和存储生产者推来的消息，而消费者自己主动来取消息，Broker自身不需要主动维护每个消费者的状态，减少了复杂度

**缺点**:

1. **消息延迟**: 拉模式下，消费者是以一定的频率轮询Broker拉取消息，这样的话消息就存在窗口期，即已经到达了Broker，但是Consumer还没有发起轮询请求是否出现新的消息。轮询频率过高又会导致Broker压力过大，而降低请求频率，又会导致消息延迟时间增加

2. **消息忙请求**: 拉模式下，即使Broker里长时间没有任何消息，但是消费者不知道，它们只能通过不断地轮询做无用功，忙于发送请求但是没有任何回应，浪费了网络资源

**适用场景**: 拉模式适合消息的批量发送，由消费者主动发起拉取请求，可以将一段时间内缓存的消息全部或部分取走，适用于消息量较大、消息实时性相对来说没那么高的场景。而且对于Broker而言，消费者可以是异构的，消费能力各不相同，Broker作为相对中心化的消息存储中间件，不应该存在依赖于消费者的倾向。

#### 各个消息队列的推拉模式选择

以吞吐量为优点的**RocketMQ**和**Kafka**(单机吞吐量都达到了十万级，比RabbitMQ高出一个数量级)默认选择了拉模式，但是针对拉模式消息实时性不高的缺点，这两种消息队列都使用了**长轮询**进行优化:

即，消费者发起拉请求后，将该请求的超时时间设置得比较长(一般为30s或者自定义时间)，Broker挂起该请求，一旦该请求关联的Topic或者Queue中出现了新的消息或者新消息数量达到消费者指定的量级，Broker就会响应之前挂起的请求，将消息打包发送给消费者。对于消费者来说，如果之前发起的长轮询请求超时，则会再次发起长轮询请求。

以时效性为优点的**RabbitMQ**(微秒级)默认采用的是推模式，消费者订阅信道后(`channel.basicConsume(queueName, consumer)`)，只要新的消息到达了Broker,就会主动推送给消费者，而不需要消费者主动来拉取(推送速度受`channel.basicQos`限制)，所以RabbitMQ的消息实时性非常高

当然RabbitMQ也提供了拉模式的交互方式，比如消费者不想持续订阅某个队列，可以利用`channel.basicGet`方法主动去Broker拉取单条信息，当然这样就不能保证消息的实时性

### 消息的顺序性如何保证

引入MQ对微服务进行解耦后，初衷是比较好的，但是某些业务间天然具有有序性，如果发送到MQ后异步进行处理就可能会出现乱序问题，无法保证消息的顺序性

一般而言，消息的顺序性可以分为同种业务的顺序性和不同业务的顺序性两方面进行考量，且都有不同的解决办法

1. **同种业务的顺序性**: 假设有一个积分累加的业务，订单结算服务的不同实例在结算订单时发送累加积分的消息，对于同一个用户而言这些积分累加的消息是有序的，要满足时间或订单号等顺序

2. **不同业务的顺序性**: 不同业务间可能存在后序的某个业务需要前序业务的处理结果作为参数，而消息队列不能保证位于不同队列里的这些消息能够有序地发送给对应服务进行处理，无法保证消息的顺序性

生产者到队列再到消费者，它们之间的关系通常是**多对多对多**的，一般也有两种方法：

- 对于同一**生产者实例**，处理同种业务的消息时，按照顺序发送到同一队列中(给定路由规则或指定投递的队列、分区等方式)，并且保证只有一个消费者实例订阅该队列，有序处理这些消息
  
  保证每个生产者实例固定对应1个队列，再固定对应一个消费者实例，这种情况下能够保证消息的顺序性。但是这种方法通常不具备扩展性，因为生产者实例和消费者实例的数量不可能总是一一对应，且消息队列能够建立的队列数量也是有限的

  ![消息的顺序性-一对一](https://s2.loli.net/2023/05/10/GmehOfo1WzYHLxV.png)

- 对于更通用的场景，比如不同的生产者实例向不同的队列中投递了具有顺序性的消息，同时存在许多消费者实例订阅了这些不同的队列，仅依靠MQ和生产者消费者自己的话很难维护顺序关系，所以要引入第三方记录顺序消息消费表，比如**Redis**就可以作为这个第三方

  ![消息的顺序性-多对多](https://s2.loli.net/2023/05/10/hIOtVbL3kuZAGs8.png)

  生产者在发送消息前，先往Redis中写入对应消息的编号信息，某个消费者实例取到消息执行消费前，根据该消息的编号去Redis中查询其前序消息是否已经被消费过:
  
  1. 如果其前序消息处于*已消费*状态，那么当前消费者就对该消息进行消费，并去Redis中将对应编号的消息更改为*已消费*状态

  2. 如果其前序消息还处于*未消费*状态，消费者可以选择拒绝消费该消息，重新打回到消息队列中再进行投递(RabbitMQ中对应`basicReject`指令，同时将`requeue`参数设为`true`保证被拒绝的消息重新入队)。或者为了减轻消息队列的压力，消费者实例可以本地缓存该消息，开启一个后台线程轮询Redis中前序消息的消费状态，一旦前序消息已被消费，则取出缓存中的消息进行消费

     > 为了避免消费者重启导致内存中缓存消息丢失，可以将等待被消费的消息缓存到Redis或者持久化到数据库中

### 消息可靠性的保证措施

消息的可靠性主要是在三个消息转移/存储的阶段

- 生产者到RabbitMQ：生产者发送消息给RabbitMQ后，需要知道自己是否成功发送了消息，一般称为 消息发送确认，RabbitMQ提供事务机制或者Confirm机制以实现生产者确认机制
  
  1. **事务机制**: 通过`txSelect()`将信道设置为事务模式，只有RabbitMQ确实接收了该消息，事务才能提交成功，否则便会回滚并重发消息，非常影响性能，且是阻塞过程
  
  2. **消息应答机制**：通过`confirmSelect()`将信道设置为Confirm模式，所有在该信道上发布的消息都会被分配1个唯一ID，当生产者发送消息(`Basic.Publish`消息，携带消息头和消息体)给RabbitMQ后，如果RabbitMQ成功通过交换机将这条消息路由到目的队列中，它就会发布一条`Basic.Ack`确认消息(携带消息的唯一ID)告知生产者。生产者如果发现超时未收到`Basic.Ack`，就会重传该消息；如果收到`Basic.NAck`，生产者就可以做对应的处理

  3. 对于无法路由到其匹配队列的消息，如果消息头中添加了属性`mandatory=true`，当RabbitMQ的交换机无法无法路由该消息时，就会发送`Basic.Return`，将该消息返还给生产者

- RabbitMQ本身：

  1. 将消息持久化到本地，节点宕机了也能从本地恢复(Feature为`D`即表示该队列是持久化队列)

  2. **镜像集群**：通过`ha-mode`指明镜像队列模式，包括`all`(在集群所有节点上进行镜像)、`exactly`(在指定个数节点上进行镜像)、`nodes`(在指定节点上进行镜像)；同时通过`ha-params`给出`ha-mode`不同模式下需要的参数比如节点个数或者节点名称。最后通过`ha-sync-mode`设定队列中消息的同步方式，包括自动和手动。注意设定镜像时可以使用正则表达式匹配想要镜像的队列名称

     ```sh
     rabbitmqctl set_policy [-p <vhost>] [--priority <priority>] [--apply-to <apply-to>] <name> <pattern>  <definition>
     ```

     > 注意**主从集群**并不能保证消息可靠性，队列里的消息只存在于主节点，从节点只负责队列转发，当订阅了从节点的消费者需要消费消息时，从节点是去主节点对应队列中取出消息再转发，一旦主节点宕机，队列里的消息还是丢失了

- RabbitMQ到消费者:

  - **消息应答机制**：

    当RabbitMQ向消费者传递了一个消息，如果该消费者还没消费就宕机，就会导致该消息丢失，为了保证消息的可靠性，消费者会在**接收到消息并处理完成后**发送`basicAck`这条应答消息告知RabbitMQ可以删除该消息了

    自然也会有拒绝消息的应答：`basicNack`(否定应答，我处理不了还请交给其他人处理)、`basicReject`(拒绝应答，表示拒绝处理该消息可以直接丢弃)

    当消费者因为宕机或者抛出异常导致一直没有发送ack应答消息，那么RabbitMQ就认为该消息没有被处理，将其重新入队，分发给其他消费者，保证消息不会丢失

  - **死信队列**: 死信队列通过死信交换机实现，当消息因为消息被拒(`Basic.Reject / Basic.Nack`)且`requeue=false`、或者消息TTL到期、或者队列已满无法添加，这个Dead Message就会被DLX(Dead-Letter-Exchange，死信交换机)发送到与其绑定的死信队列里。服务可以设置一个专门监听死信队列的Consumer，针对死信消息进行异常恢复，如果恢复不成功可以继续转存回死信队列或者其他队列中。死信队列可以保留案发现场，即保存出现异常的那条原始消息

### 如何保证消息不被重复消费

#### 导致出现消息重复消费的原因

生产者到MQ再到消费者的各个阶段都有可能会出现消息重复消费:

1. **生产者**: 生产者可能会重复推送一条相同消息到MQ中，在**没有实现接口幂等性**时会出现这种情况，比如Controller接口被重复调用了2次

2. **MQ**: 消费者消费完消息准备响应ack消息时，MQ突然宕机，没有接收到该ack消息，MQ恢复后认为消费者还未消费完这条消息，于是再次推送

3. **消费者**: 消费者消费完消息准备响应ack消息时，消费者突然宕机，消费者服务重启后MQ因为没有收到ack消息所以认为消费者没有消费该消息，于是再次推送

![消息重复消费](https://s2.loli.net/2023/04/17/sAEN3uPdnDwkQzX.png)

上图中，第一次消费后的Ack失败既可能是MQ宕机也可能是消费者宕机而导致的

#### 解决方案

下面的解决方案是从各个角度考虑的，由浅至深

1. 使用数据库唯一键进行约束

   数据库表中的`Unique`列可以利用唯一性去重，但是**只适用于数据新增场景**，即只有插入数据时因为唯一键约束而导致重复消费无法成功，但是如果是修改的操作仍然会重复消费成功，局限性比较大

2. 使用乐观锁的一种实现：版本号机制

   针对数据修改场景，以更新订单状态为例，生产者在发送的消息中携带目标修改字段的版本号，数据库表中也新增对应的版本号列。一旦出现重复消费问题，由于第一次消费时修改字段的版本号自增，第二次重复消费时携带的版本号对不上当前表中目标字段的版本号，防止了重复消费

   **缺点**:

   - 首先，如果更新字段较多，且具有不同的更新场景(比如排列组合不同数量的字段)，由于版本号还是要存储在表中，这就会导致表中字段增多

   - 其次，不同更新场景下部分修改字段是重合的，如果在不同更新场景下生成了多条消息，由于它们要修改的字段交集其版本号一致，导致排在后面的消息无法被消费

3. 简单的添加消息去重判断，在消费时增加数据库判断

   消费者消费消息前，直接去数据库查看是否已存在对应纪录(包括插入或者修改的情况)，如果存在就直接结束，认为消费完成，否则的话再执行业务代码进行消费

   **缺点**:

   消费者消费消息也是需要时间的，如果在这个时间差内产生重复消息(比如MQ的Broker重启或者生产者快速重发)，此时数据库表中对应纪录仍不存在，还是会有重复消费的风险

4. **最后的完善方案**: 增加一个去重表，用以表示消息的"消费中"/"已消费"状态，对于**消费中**的消息设置一个过期时间，见下面流程图:

   ![基于消息去重表解决重复消费](https://s2.loli.net/2023/04/17/MHexOKVJGEW7INm.png)

   由于去重表的存在，一条新的消息首先插入到去重表中，并标记为"消费中"状态，同时为其设置一个过期时间

   如果出现了重复消息，在插入到去重表时发现表中已存在"消费中"或者"已消费"的相同消息，插入将会失败，再根据去重表中对应消息的消费状态:

   - 如果是"已消费"，说明当前重复消息没必要再次消费，直接返回成功

   - 如果仍处于"消费中"，为了保证前面的消息能够正确被消费，本条重复消息并不直接丢弃，而是压入延时队列等待延时消费
  
  前面正常消费的第一条消息，执行业务逻辑时如果出现异常或者业务逻辑失败，就认为这条消息消费失败，同时**去消息去重表中删除"消费中"状态的记录**，然后将该消息重新压入延时队列等待延时消费

  如果执行业务成功则说明消费成功，将消息去重表中的"消费中"状态改为"已消费"(同时删去过期时间)，这样这条消费记录就持久化在消息去重表里，后续的重复消费消息插入去重表时发现已经消费成功，防止了重复消费问题

  > 之所以要对处于**消费中**的消息设置过期时间，是因为在修改消息去重表相关记录时也可能会出现意外状况导致修改状态失败，如果一条"消费中"消息一直卡在去重表中，那么后续的消费消息永远无法进入消费阶段而导致业务出现重大问题

  消息去重表是要保存在一个存储媒介中(各种类型的数据库)，Redis非常适合用于实现消息去重表，因为`expire`的存在，为处于“消费中”状态的消息设置过期时间，超时后自动删除
