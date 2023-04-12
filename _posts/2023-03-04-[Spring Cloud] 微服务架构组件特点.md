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

### 数据模型

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
