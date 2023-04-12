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

   - 利用`AnnotationBeanNameGenerator`生成BeanName(`@Component`注解可以配置`BeanName`参数，没有的话默认按照类名生成)，最后将类上使用的其他注解赋值给`BeanDefinition`

   - 最后将`BeanName`和`BeanDefinition`存入`beanDefinitionMap<BeanName, BeanDefinition>`中，完成注册

2. Spring开始生成Bean的**原始对象**:

   - 遍历beanDefinitionMap，得到BeanName和对应的BeanDefinition

   - 根据Bean的类信息，推断构造方法: 优先使用`@AutoWired`注解的构造方法，如果没有的话默认使用无参构造方法(如果这个类**只定义了一个**有参构造方法，则使用该方法)

   - 利用Java提供的反射API，根据推断出的构造方法实例化一个对象，称作原始对象

3. 对原始对象进行**依赖注入**，填充原始对象中的属性:

   - 属性值利用`set()`方法填充

   - 涉及到其他Bean(比如有`@AutoWired`要求Spring自动注入的其他Bean)，首先ByType再ByName去IOC容器(单例池)中取出对应的Bean对象执行注入，如果不存在则去创建目标Bean，详见[Bean的依赖注入过程](#bean的依赖注入过程)一节
  
   > 当然这其中会出现循环依赖问题:`A` Bean 依赖 `B` Bean，`B` Bean 依赖 `A` Bean，创建`A` Bean时触发`B` Bean的创建，然而`A` Bean也正在创建之中
   > Spring利用三级缓存解决了循环依赖问题，详见[Bean的循环依赖](#bean的循环依赖问题与解决方式)一节

4. 处理Aware回调，若该类实现了`*Aware`接口，调用对应的`set*()`方法:

   比如`BeanNameAware`、`BeanClassLoaderAware`、`BeanFactoryAware`这三个接口，分别对应BeanName、`ClassLoader`对象实例、`BeanFactory`对象实例

5. 初始化前(存在`BeanPostProcessor`对象，可以有很多个)，进行`BeanPostProcessor`的前置处理

   执行`postProcessBeforeInitialization()`方法

6. 初始化:

   - 如果Bean实现了`InitializingBean`接口(利用`instanceof`判断)，执行`afterPropertiesSet()`方法

   - 配置文件中Bean的属性里指定了`initMethod()`方法或者`@Bean(initMethod="")`给定了初始化方法，则去执行对应的`initMethod()`

7. 初始化后(存在`BeanPostProcessor`对象)，进行`BeanPostProcessor`的后置处理

   执行`postProcessAfterInitialization()`方法，这个时候AOP会根据该Bean的原始对象生成代理对象

8. 正常使用，需要该Bean的时候由IOC自动注入该Bean

## Bean的依赖注入过程

## Bean的循环依赖问题与解决方式

## Bean的线程安全问题

线程安全问题是从JVM运行时考量的，虽然大部分Bean都是以单例模式存在，但是说到底Bean只是一个概念，实际还是一个受JVM管理的对象，对于这种单一对象自然也会存在并发情况下的线程安全问题

但是，大部分Bean是无状态的(比如Controller、Serivce、DAO等)，即内部没有任何可变的成员变量，只有各种方法体，这个时候无所谓线程安全问题

如果定义了**可变**成员变量，就有可能会出现线程安全问题，比如多个线程在Bean中方法里读写该变量，建议是将类似的变量加入到ThreadLocal中，让每个线程从线程私有的ThreadLocalMap里取出变量读写即可
