---
layout:     post
title:      "[Spring] 限流组件自定义-基于注解+AOP"
subtitle:   "利用Guava/Redis实现可扩展的无侵入注解式限流方案"
author:     Penistrong
date:       2023-07-10 09:49:35 +0800
categories: jekyll update
catalog:    true
mathjax:    false
katex:      true
tags:
    - Spring
    - Java
---

# 限流组件自定义

> **包名约定**: org.penistrong.wheel.limiter

## 为什么要自定义限流组件

在微服务架构流行的当下，有很多中间件实现了限流功能，比如著名的Sentinel、Hystrix等，这些限流组件通常为了易用性和扩展性增加了很多冗余功能

有时候只是想进行简单的限流，但是却要引入一个庞大的限流中间件同时还需要维护配置文件、规则文件等，有种大炮打蚊子的感觉

所以自定义开发一个基于注解+AOP的简单限流中间件，一方面简化了依赖，另一方面也学习了新的知识(至少能够暂时跳出CRUD的舒适圈)

## 注解式限流组件设计

首先，由于需求是无侵入式限流，所以使用注解是必须的，简单起见注解的粒度仅为方法级别，对想要限流的接口加上注解即可。再使用AOP拦截被注解的接口，实现限流逻辑

其次，限流组件的具体实现可以灵活切换且易于扩展，未来可以加入使用其他限流算法的实现

### 注解定义

注解是项目使用限流组件的接入点，因此要定义好注解的属性，以便于使用者进行配置

不管采用的是何种限流算法(详见另一篇博客[负载均衡算法与限流算法]({% post_url 2023-04-07-[分布式] 负载均衡算法与限流算法 %}))，大致都可以理解为一段时间窗口内限制流量的最大值，所以限流注解至少需要如下3个基本属性:

- 限流资源的唯一`key`
- 限流时间窗口大小`window`
- 窗口内的最大流量`limit`

```java
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
@Documented
public @interface Limit {
    /**
     * 限流资源的key, 保持唯一，不同的接口进行不同的流量控制
     */
    String key() default "";

    /**
     * 限流时间窗口大小，单位ms
     */
    long window() default 1000;

    /**
     * 时间窗口内的最大流量
     */
    long limit() default 10;

    /**
     * 获取不到令牌时的最大等待时间，单位ms
     */
    long timeout() default 100;

    /**
     * 使用RedisLimiter时的ZSet键过期时间, 单位s
     */
    long expire() default 10;

    /**
     * 接口降级时的提示消息
     */
    String msg() default "接口限流，稍后再试";
}
```

`Limit`注解对应的实体类`Limiter`如下所示，在接下来的AOP切面处进行解析:

```java
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Limiter {
    String resourceKey;

    long window;

    long limit;

    long timeout;

    long expire;

    String msg;
}
```

### AOP切面定义

对被注解接口进行限流的执行逻辑由Spring AOP实现，将注解的属性转换为实际的`Limiter`对象，由`LimiterManager`接口的实现类执行限流

```Java
@Aspect
@EnableAspectJAutoProxy(proxyTargetClass = true)
@Component
@Conditional(LimitAspectCondition.class)
public class LimitAspect {

    @Setter(onMethod_ = @Autowired)
    private LimiterManager limiterManager;

    @Pointcut("@annotation(limit)")
    private void checkLimit(Limit limit) {}

    @Before(value = "checkLimit(limit)", argNames = "joinPoint,limit")
    public void before(JoinPoint joinPoint, Limit limit) {
        Limiter limiter = Limiter.builder()
                .resourceKey(limit.key())
                .window(limit.window())
                .limit(limit.limit())
                .timeout(limit.timeout())
                .expire(limit.expire())
                .msg(limit.msg())
                .build();

        if (!limiterManager.tryAccess(limiter)) {
            throw new LimiterException(limiter.getMsg());
        }
    }
}
```

切面类上的`@Conditional`注解决定限流组件切面是否需要被注入IOC容器，这里使用`LimitAspectCondition`类实现，该类实现了`Condition`接口，重写`matches`方法，仅当配置文件中`limiter.enabled`属性存在且为`true`时才会注入IOC容器

```java
public class LimitAspectCondition implements Condition {
    @Override
    public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
        return context.getEnvironment().containsProperty(LimiterConfigConstant.LIMIT_ENABLED) &&
                Boolean.TRUE.equals(context.getEnvironment().getProperty(LimiterConfigConstant.LIMIT_ENABLED, Boolean.class));
    }
}

// in LimiterConfigConstant.java
public static final String LIMIT_ENABLED = "limiter.enabled";
```

### 异常定义

限流成功时需要抛出异常进行处理，继承`RuntimeException`实现自定义限流异常类`LimiterException`，可以在**异常捕获切面**处进行捕获并以统一返回值结构包裹后返回给前端

```java
@Data
public class LimiterException extends RuntimeException {

    public LimiterException(String msg) {
        super(ErrorCode.FAIL_OPERATION, msg);
    }

    public LimiterException(Exception e) {
        super(ErrorCode.FAIL_OPERATION, e);
    }

    public LimiterException(String msg, Exception e) {
        super(ErrorCode.FAIL_OPERATION, e);
        this.setMessage(msg);
    }
}
```

## 限流组件实现类

由于需要满足限流算法实际实现的可扩展性，因此提取各个限流组件的公共逻辑到`LimiterManager`接口中，根据配置文件决定实际的限流组件实现类，这样AOP切面只需执行接口定义的公共限流方法而无需关心具体的实现类

```java
public interface LimiterManager {
    /**
     * 被限流注解标记的资源尝试获取限流令牌
     * @param limiter 使用的Limiter注解映射的实体类
     * @return true: 获取到令牌，false: 未获取到令牌
     */
    boolean tryAccess(Limiter limiter);
}
```

限流组件配置类如下所示，目前只有两种实现类，分别是基于Guava的本地令牌桶限流和基于Redis的分布式滑动窗口限流，利用`@ConditionalOnProperty`根据配置文件定义的限流组件类型进行切换

```java
@Configuration
public class LimiterConfiguration {

    @Bean
    @ConditionalOnProperty(name = LimiterConfigConstant.LIMIT_TYPE, havingValue = "local")
    public LimiterManager guavaLimiter() {
        return new GuavaLimiter();
    }

    @Bean
    @ConditionalOnProperty(name = LimiterConfigConstant.LIMIT_TYPE, havingValue = "redis")
    public LimiterManager redisLimiter(StringRedisTemplate redisTemplate) {
        DefaultRedisScript<Long> redisScript = new DefaultRedisScript<>();
        redisScript.setScriptSource(new ResourceScriptSource(new ClassPathResource("redisLimiter.lua")));
        redisScript.setResultType(Long.class);
        return new RedisLimiter(redisTemplate, redisScript);
    }
}
```

### 基于Guava的本地限流

Google Guava提供了基于令牌桶的限流算法实现，使用`RateLimiter`类进行限流即可，注意该实现是基于`PermitsPerSecond`作为令牌数量上限，因此需要根据限流注解的`window`和`limit`计算qps大小作为参数传入

在`GuavaLimiter`类中，使用`ConcurrentHashMap`缓存每个被限流资源的`RateLimiter`对象，将`resourceKey`作为key，`RateLimiter`对象作为value，每次请求时从缓存中获取`RateLimiter`对象，如果不存在则创建

调用`RateLimiter`对象的`tryAcquire`方法尝试获取令牌，如果获取到令牌则返回true，否则返回false

```java
@Slf4j
public class GuavaLimiter implements LimiterManager {

    private final Map<String, RateLimiter> limiterMap = Maps.newConcurrentMap();

    @Override
    public boolean tryAccess(Limiter limiter) {
        RateLimiter rateLimiter = getRateLimiter(limiter);

        if (Objects.isNull(rateLimiter)){
            return false;
        }
        boolean canAccess = rateLimiter.tryAcquire(limiter.getTimeout(), TimeUnit.MILLISECONDS);

        log.info("Resource [{}] try to acquire limiter-token, result is [{}]", limiter.getResourceKey(), canAccess);

        return canAccess;
    }

    public RateLimiter getRateLimiter(Limiter limiter) {
        String key = limiter.getResourceKey();
        if (limiterMap.containsKey(key)) {
            return limiterMap.get(key);
        }
        // PPS(Permits Per Second)设置为@Limit注解定义的qps值(粒度只为调用对应方法的频率)
        // qps = limit / (window / 1000)
        RateLimiter rateLimiter = RateLimiter.create(
                (double) limiter.getLimit() / TimeUnit.MILLISECONDS.toSeconds(limiter.getWindow())
        );
        limiterMap.put(key, rateLimiter);
        return rateLimiter;
    }
}
```

### 基于Redis的分布式限流

基于Guava的单机实现很好理解，但是在分布式环境下，如果服务集群同时运行了多个实例，而使用者关心的是**基于服务的限流**而不是基于实例的限流，因此需要引入分布式限流，不同实例的相同接口，被限流时需要共享限流状态

引入Redis分布式锁的同时，为了保证Redis操作的原子性需要以Lua脚本的形式执行操作，这样就可以保证多个Redis操作的原子性，从而保证分布式限流的正确性

```java
@Slf4j
@RequiredArgsConstructor
public class RedisLimiter implements LimiterManager{

    private final StringRedisTemplate redisTemplate;

    private final RedisScript<Long> redisScript;

    @Override
    public boolean tryAccess(Limiter limiter) {
        String resourceKey = Optional.ofNullable(limiter.getResourceKey()).orElseThrow(
                () -> new LimiterException("Resource key must not be null")
        );

        // result > 0说明获取到了分布式锁且返回值为当前滑动窗口内的请求数量，可以继续执行业务逻辑
        long curTime = System.currentTimeMillis();
        Long result = redisTemplate.execute(
                redisScript,
                Collections.singletonList(resourceKey),
                String.valueOf(curTime),
                String.valueOf(limiter.getWindow()),
                String.valueOf(limiter.getLimit()),
                String.valueOf(limiter.getTimeout()),
                String.valueOf(limiter.getExpire()),
                curTime + "-" + RandomUtil.randomInt()
        );

        log.info("Resource [{}] try to acquire limiter-token[{}/{}], result is [{}]",
                resourceKey,
                result > 0 ? result : -1,
                limiter.getLimit(),
                result > 0);

        return result > 0;
    }
}
```

上述代码中需要注意两点:

1. RedisTemplate的序列化器最好使用`StringRedisSerializer`(所以这里直接使用默认提供的`StringRedisTemplate`)，保证传值给Lua脚本时参数的解析不会出现序列化问题

2. `redisScript`和`redisTemplate`都是在`LimiterConfiguration`配置类里构造Bean时注入的，前者还需要定义脚本的返回值类型(`Long.class`)

限流算法采用滑动窗口限流，利用`ZSet`数据结构在每次获取令牌时记录当前时间戳，然后清理过期时间戳，最后统计当前时间窗口内的请求数量，如果请求数量小于限流阈值则返回true，否则返回false

`redisLimiter.lua`脚本如下所示:

```lua
-- 获取唯一资源key
local key = KEYS[1]

-- ARGV中的参数依次为:
-- ARGV[1]: 限流毫秒时间戳
-- ARGV[2]: 限流时间窗口大小, 单位ms
-- ARGV[4]: 获取不到令牌时的最大等待时间, 单位ms
-- ARGV[5]: Redis Key过期时间, 单位s
-- ARGV[6]: 有序集成员元素值
local curTime = tonumber(ARGV[1])
local windowTime = tonumber(ARGV[2])
local limitCount = tonumber(ARGV[3])
local maxWaitTime = tonumber(ARGV[4])
local expireTime = tonumber(ARGV[5])
local value = ARGV[6]

-- 移除时间窗口之前的过期记录
redis.call("ZREMRANGEBYSCORE", key, 0, curTime - windowTime)

local curCount = tonumber(redis.call('ZCARD', key))
local nextCount = curCount + 1

-- 返回0表示超过限流阈值，没有获取到分布式锁
if nextCount > limitCount then
    return 0
else
    redis.call("ZADD", key, curTime, value)
    redis.call("EXPIRE", key, expireTime)
    return nextCount
end
```

## 配置为Spring-Boot-Starter

利用Spring Boot自动配置的思想，让引入该限流组件依赖的项目不需要手动编写配置类，仅需编辑配置文件即可开启自动配置

Spring Boot 3.0之后，在`resources`资源目录下新建`META-INF/spring`目录，并在其中添加`org.springframework.boot.autoconfigure.AutoConfiguration.imports`文件，加入配置类的全限定名即可

```properties
org.penistrong.wheel.limiter.config.LimiterConfiguration
org.penistrong.wheel.limiter.aop.LimitAspect
```

## 包结构一览

![限流组件自定义.png](https://s2.loli.net/2023/07/10/UocYR1BuIsgCEKa.png)

## 源码

限流组件作为轮子项目的子模块存在，仓库地址如下

[https://github.com/Penistrong/Java-Wheels/tree/master/limiter](https://github.com/Penistrong/Java-Wheels/tree/master/limiter)