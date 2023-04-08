---
layout:     post
title:      "[Java] Synchronized与ReentrantLock"
subtitle:   "Java中的两种悲观锁"
author:     Penistrong
date:       2023-04-08 09:24:15 +0800
categories: java concurrent
catalog:    true
mathjax:    false
katex:      true
tags:
    - Java
    - Concurrent
---

# Java的悲观锁实现

Java的悲观锁实现有两种，一种是JVM中实现的`synchronized`关键字，由虚拟机对其优化；一种是JDK实现的`ReentrantLock`，加锁和解锁过程由程序员通过API提供的`lock()`、`try_lock()`、`unlock()`方法手动控制

## 公平锁与非公平锁

锁的公平性是针对加锁时的动作：

1. 如果是公平锁，线程想要竞争该锁时如果发现有其他线程在排队，则当前线程也按照顺序进行排队
2. 如果是非公平锁，不会检查是否有其他线程在排队等锁，而是直接尝试竞争该锁

不管是公平锁还是非公平锁，一旦没有竞争到锁，都会进行排队，当锁被释放时，都是优先唤醒队列中排在最前面的线程，即锁的公平性只体现在了线程加锁阶段，线程被唤醒时都是公平的，按照排队顺序唤醒

## Synchronized

### 锁升级过程

*JDK6*之后引入了自旋锁、偏向锁、轻量级锁、重量级锁

## AQS

由JDK实现的`ReentrantLock`是基于AQS(AbstractQueuedSynchronizer, 抽象队列同步器)实现的，所以先要了解一下AQS的原理

### AQS核心思想

如果被请求的共享资源是空闲的，则将当前请求资源的线程设置为有效工作线程，并且将该共享资源设置为锁定状态

如果被请求的共享资源已锁定(被占用)，那么就需要一种线程排队阻塞等待并在资源空闲时唤醒线程的队列机制，AQS基于CLH锁(三个人名: Craig, Landin, and Hagersten)实现了一个线程等待队列

AQS中将资源定为`volatile int`类型成员变量`state`，表示当前同步状态，并内置一个CLH队列，头部为当前占用线程，尔后依次为排队等待的其他线程

暂时获取不到锁的线程会被封装为CLH队列的一个节点(Node)，该Node保存了线程的引用(thread)、当前节点在队列中的状态(`waitStatus`)、前驱节点(`prev`)、后继节点(`next`)

![CLH队列锁结构](https://s2.loli.net/2023/04/08/9LHO2fUgvPQmSpT.png)

同步状态`state`可以通过AQS提供的`getState()`、`setState()`和`compareAndSetState()`进行读写操作:

```java
// 返回同步状态的当前值
protected final int getState() {
    return state;
}
// 设置同步状态的值
protected final void setState(int newState) {
    state = newState;
}
// 利用CAS操作将同步状态值设置为给定值update，如果当前同步状态的值等于期望值expect
protected final boolean compareAndSetState(int expect, int update) {
    return unsafe.compareAndSwapInt(this, stateOffset, expect, update);
}
```

### AQS资源共享方式

AQS定义了两种资源共享方式:

- Exclusive(独占锁)：只有一个线程能执行，比如`ReentrantLock`
- Share(共享锁)：多个线程可同时执行，比如`CountDownLatch`和`Semaphore`

实现不同的资源共享方式，只需要继承AQS并重写指定方法，将AQS组合在自定义同步器中，调用AQS的模板方法，尔后其会调用自定义同步器重写的方法

AQS只提供了5个钩子方法，以实现上述的模板方法模式:

```java
//独占方式。尝试获取资源，成功则返回true，失败则返回false。
protected boolean tryAcquire(int)

//独占方式。尝试释放资源，成功则返回true，失败则返回false。
protected boolean tryRelease(int)

//共享方式。尝试获取资源。负数表示失败；0表示成功，但没有剩余可用资源；正数表示成功，且有剩余资源。
protected int tryAcquireShared(int)

//共享方式。尝试释放资源，成功则返回true，失败则返回false。
protected boolean tryReleaseShared(int)

//该线程是否正在独占资源。只有用到condition才需要去实现它。
protected boolean isHeldExclusively()
```

## ReentrantLock

ReentranLock的内部类`Sync`队列继承自AQS，即线程在竞争ReentrantLock提供的锁时，底层都会使用`Sync`队列进行排队

根据ReentrantLock初始化时给定的`boolean fair`参数决定是否是公平锁，加锁时:

- 如果是公平锁，检查`Sync`队列中是否有线程在排队，有则加入队列也进行排队
- 如果是非公平锁，不去检查`Sync`队列是否有线程在排队，直接尝试插队竞争该锁

加锁时的流程如下:

1. `state`初始值为0,表示未锁定状态

2. 线程A调用`lock()`时，该方法内被会调用AQS的`tryAcquire()`方法以独占方式获取该锁并将`state += 1`

3. 由于ReentrantLock是可重入的，线程A自己可以重复获取该锁，并将`state`累加，但是获取多少次就要释放多少次，保证线程A完全释放该锁时`state`同步状态归零

4. 其他线程想要`lock()`时就会失败并进入Sync队列中等待，直到线程A执行`unlock()`并且`state == 0`时，才能唤醒队列中的线程获取该锁(如果是非公平锁，这个时候也可能会有其他线程刚好发起`lock()`请求进行插队)

### try_lock()与lock()的区别

`lock()`方法为阻塞加锁方法，线程会阻塞到获取锁为止，且方法没有返回值

`try_lock()`方法为非阻塞加锁方法，尝试一次加锁，如果成功则返回true，失败则返回false，开发者可以控制下方代码是否需要继续执行，而不是一直阻塞到加到锁为止

## 死锁原因与避免

Java中如果出现死锁，其4个充分必要条件如下：

1. **互斥**:一个资源每次只能被一个线程使用

2. **请求保持**:一个线程在阻塞等待某个资源，而这个被占用的资源始终没被释放

3. **无法剥夺**:一个线程已经获得的资源，在未使用完之前，无法强行剥夺该资源

4. **环路等待**:若干线程形成头尾相接的环路资源等待关系

要避免死锁的发生，只需要破坏以上4个条件中的任意一个即可，但是在并发环境中，前3个条件是锁必须具备的条件。所以在实际的Java并发编程中，要避免死锁就要破坏线程的环路等待关系

一般而言，实际开发中要注意:

1. 加锁顺序: 每个线程对同一批资源进行竞争时，保证加锁顺序相同(这样就不会出现你持有我需要的锁，我持有你需要的锁这样的死循环)

2. 加锁时限: 针对锁设置一个超时时间，如果超过该时间还没有获取到锁，则终止本次对资源的竞争，释放之前得到的所有锁

3. 死锁检查: 这是死锁避免的预防机制，可以用`jstack`等工具检测JVM中是否出现死锁，就可以溯源并解决
