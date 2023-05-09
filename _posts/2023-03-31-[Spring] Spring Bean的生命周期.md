---
layout:     post
title:      "[Spring] Spring Bean"
subtitle:   "Details in Bean Life Circle"
author:     Penistrong
date:       2023-03-31 10:12:33 +0800
categories: java spring
catalog:    true
mathjax:    false
katex:      true
tags:
    - Java
    - Spring
---

# SPring Bean

Spring框架提供的两大核心功能就是**IOC**(Inversion Of Control)控制反转和**AOP**(Aspect Oriented Programming)面向切面编程

Spring作为轻量级的开发框架，集成了许多模块，其存在的使命就是为了提高程序员的开发效率，而IOC和AOP的实现都离开不了Spring对Bean的管理

Bean被创建后交由Spring的IOC容器进行管理，而AOP这个面向切面编程的思想也离不开IOC容器: 切面处的代理对象是在创建目标对象对应的Bean的时候一同生成的，尔后这个代理对象也会作为Bean加入IOC容器中，在需要依赖注入的其他Bean里优先注入作为代理对象的Bean

## Spring Bean的生命周期

1. Spring启动时扫描Bean的定义，注册Bean:

   - Spring扫描配置文件(XML方式)、指定包路径(`@ComponentScan`注解，如果没有的话默认扫描启动类所在包路径)下的所有`.class`字节码文件里被Bean相关注解(`@Service`、`@Controller`、`@Repository`、`@Component`)注解了的类

   - 根据`includeFilter`、`@Conditional`等注解判断相关类是否应该被解析为Bean

   - 利用`AnnotationBeanNameGenerator`生成BeanName(`@Component`注解可以配置`BeanName`参数，没有的话默认按照类名首字母小写生成，如果类名两个字母大写则Bean的名字与类名一致)，最后将类上使用的其他注解赋值给`BeanDefinition`

   - 最后将`BeanName`和`BeanDefinition`存入`BeanFactory`的`beanDefinitionMap<BeanName, BeanDefinition>`中，完成注册

2. Spring开始生成Bean的**原始对象**:

   - 利用BeanFactory获取beanDefinitionMap，根据BeanName得到其对应的BeanDefinition

   - 根据Bean的类信息，推断构造方法: 优先使用`@AutoWired`注解的构造方法，如果没有的话默认使用无参构造方法(如果这个类**只定义了一个**有参构造方法，则使用该方法)

   - 利用Java提供的反射API，根据推断出的构造方法实例化一个对象，称作原始对象

3. 对原始对象进行**依赖注入**，填充原始对象中的属性:

   - 属性值利用`set()`方法填充

   - 涉及到其他Bean(比如有`@AutoWired`要求Spring自动注入的其他Bean)，首先ByType再ByName去IOC容器(单例池)中取出对应的Bean对象执行注入，如果不存在则去创建目标Bean，详见[Bean的依赖注入过程](#bean的依赖注入过程)一节
  
   > 当然这其中会出现循环依赖问题:`A` Bean 依赖 `B` Bean，`B` Bean 依赖 `A` Bean，创建`A` Bean时触发`B` Bean的创建，然而`A` Bean也正在创建之中
   > Spring利用三级缓存解决了循环依赖问题，详见[Bean的循环依赖](#bean的循环依赖问题与解决方式)一节

4. 处理Aware回调，若该类实现了`*Aware`接口，调用对应的`set*()`方法:

   比如`BeanNameAware`、`BeanClassLoaderAware`、`BeanFactoryAware`这三个接口，分别对应BeanName、`ClassLoader`对象实例、`BeanFactory`对象实例

5. 初始化前(当前上下文中存在`BeanPostProcessor`对象，可以有很多个)，进行`BeanPostProcessor`的前置处理

   执行`postProcessBeforeInitialization()`方法

6. 初始化:

   - 如果Bean实现了`InitializingBean`接口(利用`instanceof`判断)，执行`afterPropertiesSet()`方法

   - 配置文件中Bean的属性里指定了`init-method()`方法或者`@Bean(initMethod="")`给定了初始化方法，则去执行对应的`initMethod()`

7. 初始化后(存在`BeanPostProcessor`对象)，进行`BeanPostProcessor`的后置处理

   执行`postProcessAfterInitialization()`方法，Spring AOP就是在该**初始化后**阶段利用`AnnotationAwareAspectJAutoProxyCreator`根据Bean的原始对象生成代理对象，同时代理对象里通过组合的方式引用了原始对象，保证原始对象不会被垃圾回收

8. 如果AOP接管了初始化后阶段，那么最终放入单例池的只是这个代理对象，否则放入的就是原始对象(在`postProcessAfterInitialization()`方法中其实可以完全替换掉对应的bean对象，因为**返回值是任意对象**)

9. 正常使用，需要该Bean的时候由IOC自动注入该Bean

10. Spring应用上下文关闭时，IOC容器准备关闭，要销毁其中的Bean实例:

    - 如果Bean实现了`DisposableBean`接口，执行实现的`destory()`方法

    - 配置文件中Bean的属性里指定了`destroy-method()`方法或者`@Bean(destroyMethod="")`给定了销毁方法，则去执行对应的`destoryMethod()`

## Bean的依赖注入过程

## Bean的循环依赖问题与解决方式

Bean的循环依赖问题是指，在初始化Bean `A`走到依赖注入的步骤时，发现其需要注入Bean `B`，但是单例池中并没有该Bean `B`，于是先去创建Bean `B`，但是Bean `B` 也依赖于Bean `A`，而后者还没有初始化完毕，从而导致循环依赖问题

Spring利用了三级缓存`singletonObjects`、`earlySingletonObjects`、`singletonFactories`解决该问题

### 为什么是三级缓存而不是二级缓存?

**如果只从IOC的角度上考虑**，只需要在单例池这个一级缓存之外再添加一个二级缓存`earlySingletonObjects`即可：即，在实例化Bean `A`的原始对象后，就将其加入二级缓存中，在对Bean `B`进行依赖注入时，如果单例池没有初始化完毕的Bean `A`，就去二级缓存中获取Bean `A`原始对象的引用，完成依赖注入过程

考虑到Spring的另一大核心功能**AOP**，由于AOP是在**初始化后**阶段对原始对象进行代理，利用JDK动态代理或者CGLIB生成代理对象后，**并让原始对象以组合的方式作为代理对象的字段之一**

这样就会出现一个问题，如果二级缓存中存放的是还未初始化完成(**提前暴露**)的原始对象，那么Bean `B`在初始化时如果直接使用Bean `A`的原始对象，那么Bean `A`被AOP所处理的增强逻辑就不会被Bean `B`执行(Bean `B`执行方法时用的是Bean `A`的原始对象而不是代理对象)

所以Spring需要引入第三级缓存`singletonFactories`解决AOP的问题

### 三级缓存处理过程

> 假设Bean `A`依赖Bean `B`，而Bean `A`的部分方法被AOP代理(比如`@Transactional`等)

在实例化Bean `A`的原始对象后，Spring会构造一个`ObjectFactory`存入第三级缓存`singletonFactories`中，以`<BeanName, ObjectFactory>`键值对形式存入Map中

`ObjectFactory`是一个函数式接口，其中定义的`getObject()`方法可以传入一个Lambda表达式，在Spring的处理中是传入`() -> getEarlyBeanReference(String beanName, RootBeanDefinition mbd, Object bean)`这个Lambda表达式作为该工厂接口的实现

`getEarlyBeanReference()`这个方法在`SmartInstantiationAwareBeanPostProcessor`接口中被定义，而整个Spring中只有`AbstractAutoProxyCreator`类实现了该方法，Spring AOP的处理类就是`AnnotationAwareAspectJAutoProxyCreator`，该类的父类就是`AbstractAutoProxyCreator`

```java
// in AbstractAutoProxyCreator
private final Map<Object, Object> earlyProxyReferences = new ConcurrentHashMap(16);

@Override
public Object getEarlyBeanReference(Object bean, String beanName) {
   Object cacheKey = this.getCacheKey(bean.getClass(), beanName);
   this.earlyProxyReferences.put(cacheKey, bean);
   return wrapIfNecessary(bean, beanName, cacheKey);
}
```

在依赖注入时，发现所需的Bean `B`还没有创建，于是先去初始化Bean `B`，后者的依赖注入过程中需要用到Bean `A`(由AOP的逻辑，这里注入的应该是Bean `A`的代理对象)，检查一级缓存`singletonObjects`和二级缓存`earlySingletonObjects`中是否有Bean `A`的实例。如果都没有，就去第三级缓存`singletonFactories`根据BeanName获取对应的`ObjectFactory`，执行该工厂类的`getObject()`方法就会调用传入的Lambda表达式里的`getEarlyBeanReference()`方法，提前对Bean `A`的原始对象进行AOP代理，返回代理对象**并将其放到二级缓存`earlySingletonObjects`中**，该代理对象内部持有对原始对象的引用，但是该原始对象还未完成依赖注入过程，因此不能将该代理对象直接丢到一级缓存`singletonObjects`中

尔后，Bean `B`或者依赖了Bean `A`的其他Bean就可以直接从二级缓存`earlySingletonObjects`中得到Bean `A`原始对象的代理对象，完成依赖注入过程，最终Bean `B`被存储到一级缓存`singletonObjects`里

Bean `B`创建完毕后，继续Bean `A`的依赖注入阶段，原始对象完成属性填充。尔后，循序渐进到“初始化后”阶段时，负责AOP处理的`AnnotationAwareAspectJAutoProxyCreator`(BeanPostProcessor)调用其父类`AbstractAutoProxyCreator`的`postProcessAfterInitialization()`方法，判断Bean `A`的BeanName是否已存在于`AbstractAutoProxyCreator`内部的`earlyProxyReferences`表中，若存在则说明在之前的循环依赖解决过程中已经提前进行过AOP，无需再次进行AOP，直接跳过不处理

```java
// in AbstractAutoProxyCreator
public Object postProcessAfterInitialization(@Nullable Object bean, String beanName) {
   if (bean != null) {
      Object cacheKey = this.getCacheKey(bean.getClass(), beanName);
      if (this.earlyProxyReferences.remove(cacheKey) != bean) {
            return this.wrapIfNecessary(bean, beanName, cacheKey);
      }
   }

   return bean;
}
```

最后，Bean `A`走完整个创建周期后(所有的BeanPostProcessor都执行完毕)，，此时Bean `A`的代理对象是存放在二级缓存`earlySingletonObjects`中，从二级缓存取出代理对象放入一级缓存中，解决了整个循环依赖问题

## Bean的线程安全问题

线程安全问题是从JVM运行时考量的，虽然大部分Bean都是以单例模式存在，但是说到底Bean只是一个概念，实际还是一个受JVM管理的对象，对于这种单一对象自然也会存在并发情况下的线程安全问题

但是，大部分Bean是无状态的(比如Controller、Serivce、DAO等)，即内部没有任何可变的成员变量，只有各种方法体，这个时候无所谓线程安全问题

如果定义了**可变**成员变量，就有可能会出现线程安全问题，比如多个线程在Bean中方法里读写该变量，建议是将类似的变量加入到ThreadLocal中，让每个线程从线程私有的ThreadLocalMap里取出变量读写即可

## 为什么Spring Bean默认是单例的

首先，Spring中Bean的作用域默认只有`singleton`和`prototype`两种，在基于Spring Web的ApplicationContext下还有另外4种:`request`、`session`、`global-session`、`websocket`

一般来说，无状态的Bean都是单例`singleton`作用域的，而有状态Bean如果不采取ThreadLocal的话那就配置为原型`prototype`作用域，每次获取都会创建一个新的Bean实例

Bean默认单例的好处:

- 减少对象的创建次数，Spring框架创建Bean的实例是利用Java反射API构造的，如果每次都创建新的Bean实例，反射效率比较低导致整体性能下降

- 程序整个生命周期里创建的对象就比较少，而且单例Bean可以存活很久，减少GC次数，降低STW的时间，提高了性能。单例Bean随着分代年龄的增长，最终可以晋升到老年代里，一直存在

- IOC容器`singletonObjects`就是个单例池，使用Bean时直接在单例池里根据BeanName快速获取已经创建过的Bean单例

Bean默认单例的缺点:

有状态Bean存在线程不安全问题，解决方法上一节已有
