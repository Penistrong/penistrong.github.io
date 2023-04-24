---
layout:     post
title:      "[Spring Cloud] 微服务架构组件特点"
subtitle:   "Nacos, Sentinel, Spring Cloud Gateway, RabbitMQ, etc."
author:     Penistrong
date:       2023-03-04 21:39:16 +0800
categories: java spring
catalog:    true
mathjax:    false
katex:      true
tags:
    - Java
    - Spring
    - Spring Cloud
---

# Spring Cloud 微服务架构常用组件特点

## Nacos

Nacos全称Naming and Configuration Serivce，同时扮演了服务注册中心和配置中心的角色，是分布式系统(微服务架构)中不可或缺的一角

### 注册中心 Naming Service

![Nacos服务注册与服务发现](https://s2.loli.net/2023/03/31/A7i6HqMLfotBdey.png)

Nacos集群中各个节点的数据一致性可以由两种分布式协议达成，其一是Raft协议，选举Leader进行数据写入，即CP架构；其二是Distro协议，侧重可用性(或最终一致性)的分布式一致性协议，即AP架构

Nacos注册中心可以同时使用CP+AP模式管理节点：

需要被Nacos服务注册中心(Naming服务)管理的服务实例默认以AP模式启动，如果需要设置为CP，就在配置服务实例的启动参数`spring.cloud.nacos.discovery.ephemeral=false`(默认为true)

设置为CP模式启动的节点，就是持久化节点，Nacos管理持久化节点不会因为其不在运行而主动剔除，而是将其标记为不健康状态，而这种健康检查是由Nacos发起的"主动探活"请求完成的

除了持久化节点，大部分服务实例节点都是以"临时节点"的身份存在，临时节点需要主动发送心跳请求向服务器报备自身状态

### 配置中心 Configuration Service

**经典发问**: Nacos作为配置中心时，配置数据的交互模式是服务器主动推还是客户端主动拉？

**直接答案**: 客户端主动拉取，利用长轮询(Long Polling)方式获取配置数据

**详细解析**:

配置中心的作用就是对配置进行统一管理，修改配置后应用可以动态感知，无需重启。某些场景下，通过修改某个配置项实时控制某个功能的开闭，而不是让服务集群批量重启

常规下，客户端与配置中心的数据交互方式分为两种: 推模型与拉模型

- **推模型**: 客户端与服务端建立TCP长连接，当服务器配置数据有变动，由服务器主动通过长连接将数据推送给客户端

  **优点**: 这种方式的优点在于实时性，一旦数据变动，立刻推送更新，对于客户端而言更为简单，不需要关心自身的配置数据是否有变更，只需要被动接送推送即可

  **缺点**: TCP长连接会因为网络问题导致不可用，从而出现`假死`问题，即连接状态正常但实际已无法通信，要加入心跳机制`KeepAlive`保证连接的可用性，才能保证配置数据能够正确推送

- **拉模型**: 客户端主动向服务端请求拉取配置数据，常见的方式就是普通的轮询，比如每隔3s向服务端请求一次配置数据

  **优点**: 实现简单，客户端主动拉取，服务端不用操作

  **缺点**: 无法保证数据实时性，什么时候请求？间隔多久请求？如果有很多服务实例不停地轮询配置中心，也会造成网络压力

Nacos的解决方式: 由客户端发起长轮询，配置中心不会立即返回请求结果，而是挂起请求，如果在挂起的时间内配置数据发生了变更，就立即响应客户端请求，发送配置数据；若一直无变化，则等到长轮询超时时间(默认为`30s`)后响应HTTP 304，客户端再重新发起长轮询即可

即，结合了推拉模型的优点，让客户端主动拉取，利用长轮询等待服务端返回请求，减少轮询次数降低服务端压力

#### Nacos层级划分

按照层级关系由大到小分别为:

- `namespace`: 命名空间，隔离不同环境，比如`dev`、`test`等非生产环境，默认的配置数据都放在`public`里

- `group`: 分组管理，同一环境下的不同分支需要不同的配置数据，比如A/B测试，默认分组`DEFAULT_GROUP`

- `dataId`: 键值对形式的配置数据，`key`即文件名称，`value`为文件内容

#### 数据流转过程

Nacos控制台、客户端通过发送http请求将配置数据注册到服务端，Nacos服务端将配置数据持久化到MySQL中

客户端在本地维护了一个配置文件快照，存在一个`AtomicReference<Map<String, CacheData>>`这个原子引用Map类型的`cacheMap`里: 

- key为`groupKey`，由`dataId`、`group`、`tenant`拼接而成的字符串

- value为`CacheData`对象，其字段包括`dataId`、`group`、`tenant`、`content`文件内容、`listeners`监听器、`md5`文件内容校验值

客户端调用`getConfigAndSignListener()`方法，其内部对dataId数据变更注册了监听器`addTenantListenersWithContent()`，监听器是绑定在`CacheData`对象上的，如果没有配置数据，从通过`addCacheDataIfAbsent()`方法向服务端发起长轮询获取配置，回填到`CacheData`的`content`字段里，同时利用`content`在客户端本地生成MD5值

配置文件是否改变是利用MD5进行判断，`listeners`监听器列表是一个`CopyOnWriteArrayList<ManagerListenerWrap>`对象，其中的每个`ManagerListenerWrap`持有`Listener`监听类和一个`lastCallMd5`，后者记录上一次没发生变化的Md5值，用MD5比较数据是否有更新

而客户端自己是通过`ClientWorker`对象里的线程池来轮询本地的`cacheMap`，检查每个`dataId`对应的`CacheData::md5`与`CacheData.listener.lastCallMd5`值是否不同，不相同则调用`safeNotifyListener`方法单独起一个线程，向所有对`dataId`注册过监听的客户端推送新的`content`，客户端利用`receiveConfigInfo()`方法处理自身业务

## Sentinel

大型微服务系统中高可用性的重要一环便是 **服务容错**。

高可用性保障的一种常规操作是通过搭建分布式服务集群以避免单点故障，但是在面对 **服务雪崩** 时仍不具备保障。服务集群中总会存在部分服务，其底层需要对数据库等数据源进行数据读写，假设它需要执行一段性能没有优化的SQL语句，这样的话单次DB操作的执行时间会稍长，在并发量较小的情况下通常不会存在问题，一旦并发量井喷，这种性能上的些微差距就会被迅速放大

这种情况下，该服务会迅速消耗数据库的连接资源，进而导致该服务提供接口的响应时间不断延长，而上级服务的请求又在源源不断地抵达该服务，这样接口超时就会如雪崩一般毁灭性地滚向上级服务，再淹没更上级的服务，导致整个服务集群不可用。

*Sentinel*就是一款能够应对服务雪崩的服务容错组件，它按照"内外兼修"的思路消弭服务雪崩，犹如前线的**哨兵**一样:

### 内部异常治理

Sentinel采取 **降级** 与 **熔断** 的方式处理服务集群内部出现的异常:

- 降级: 当服务调用发生响应超时、服务异常等情况时，可以转而执行**降级逻辑**，比如重试请求、恢复异常、默认返回等，降级是针对**单次**服务调用异常而执行的处理逻辑

- 熔断: 当服务异常积累到一定阈值时，比如某段时间窗口内降级请求出现了一定次数，则Sentinel会让该发起调用的微服务在一段时间内停止向目标服务发起调用，所有相关请求直接执行降级逻辑。所以熔断是**多次**服务调用异常积累后而执行的处理逻辑

### 外部流量控制

Sentinel可以通过流量整形、流量控制等方案，为每个微服务设置规则，从QPS或并发请求线程数等维度控制外界来访流量。一旦访问量超过阈值，Sentinel可以采取多重手段处理后续到达的请求

从限流算法的角度而言，常用的限流算法有滑动窗口、令牌桶、漏桶等，Sentinel的3种流控策略也是按照限流算法的思想设计的:

- 快速失败 Fast Fail: 直接丢弃请求，抛出异常`Blocked by Sentinel(flow limiting)`
  > 快速失败$\to$*滑动窗口*: 如果一段滑动时间窗口内的QPS或者并发线程数超过一定阈值，直接丢弃多余的请求

- 预热冷启动 Warm Up: 在一段规定的预热时间窗口内，由低到高逐渐拉高流量阈值，直到预设的最高阈值位置
  > 预热冷启动$\to$*令牌桶*: 通过动态调整令牌桶容量大小，流量阈值逐渐升高，达到预热效果

- 排队等待: 将后续的服务请求放入缓冲队列，如果该请求在预设的超时时间内仍未被处理，则将其移出队列丢弃
  > 排队等待$\to$*漏桶*: 所有的请求数据包放入漏桶进行排队等待，漏桶以一定的速率放行数据包，达到匀速效果

限流算法详见另一篇笔记[负载均衡与限流算法]({% post_url 2023-04-07-[分布式] 负载均衡算法与限流算法 %})

## Spring Cloud Gateway

Gateway本身就是一个微服务，它也是Nacos服务注册中心的一员。而Gateway能连接到Nacos，那它就可以接收Nacos推送的其他所有微服务的注册表(比如ip:port)，这样Gateway就可以根据本地路由规则，将请求准确无误地送达到每个微服务组件中

使用Gateway的好处就在于它的高扩展性，对微服务集群做扩容或者缩容，Gateway都能从服务注册中心获取所有服务节点的变动

### Gateway路由规则

Spring Cloud Gateway的路由规则由三部分组成:

1. **路由**: 基本单元，每个RouteLocator都有一个目标服务地址，指向当前路由规则要调用的目标服务

2. **谓词**: 路由的判断规则，满足谓词规则就会将请求进行发送，Gateway有很多内置谓词可以构造复杂路由条件

3. **过滤器**: Gateway转发请求到目标服务时，由filter处理，它采用一种过滤链(filter chain)的方式，在发送request和接收response时都会走一遍过滤器，大致分为两种过滤器: GlobalFilter(全局)和GatewayFilter(局部，针对指定路由生效)

#### 路由声明

三种方式:Java代码、yaml文件、动态路由，前两种都是硬编码，在代码或者配置文件中写死路由声明，项目启动后只会加载一次，运行期修改路由只能依靠动态路由加载

比如，Gateway可以监听Nacos Config中的文件变动，动态获取Nacos配置中心里配置的规则

#### 内置谓词

常用谓词也分3种:

1. 寻址谓词: 针对请求地址和类型做判断，比如`uri`、`path`和`method`(`RouterLocator类的成员变量`)
2. 请求参数谓词: 包括Query参数`query`、`cookie`、`header`
3. 时间谓词: 借助`before`、`after`、`between`控制当前路由的生效时间段

#### 过滤器

用一段例子演示过滤器的基础使用，下面是使用Java代码定义路由规则

```java

@Configuration
public class RoutesConfiguration {

    @Bean
    public RouteLocator declare(RouteLocatorBuilder builder) {
        return builder.routes()
                .route(route -> route
                        .path("/gateway/coupon-customer/**")
                        .filters(f -> f.stripPrefix(1))
                        .uri("lb://coupon-customer-service")
                ).route(route -> route
                        .order(1)
                        .path("/gateway/template/**")
                        .filters(f -> f.stripPrefix(1))
                        .uri("lb://coupon-template-service")
                ).route(route -> route
                        .path("/gateway/calculator/**")
                        .filters(f -> f.stripPrefix(1))
                        .uri("lb://coupon-calculation-service")
            ).build();
    }
}
```

`path`谓词约定了路由匹配规则为`/gateway/template/**`，注意上面的多个route间可以通过设置`.order()`设定路由优先级，越小越优先

`filters`过滤器里指定了一个`stripPrefix`过滤器，给定参数`1`的情况下过滤器在路由匹配后给目标微服务发送请求的时候将请求URL的前置子路径删除`1`个，变成了`/template/**`，符合微服务里定义好的Controller接口

`uri`指定了当前路由的目标转发地址，前面的`lb`即`loadBalance`，将使用本地负载均衡将请求转发到名为`coupon-template-service`的微服务

### 从Nacos Config获取动态路由表
