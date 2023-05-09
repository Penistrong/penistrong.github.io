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

`synchronized`关键字是由JVM实现的锁，在*JDK1.6*之前是十分重量级的，获得锁和释放锁时的性能消耗都很高

但是自*JDK6 Update24*后，JVM规范对`synchronized`进行了优化，引入了偏向锁和轻量级锁，并在对象头的Mark Word中添加相关标记字段，同时也引入了锁升级过程和锁优化技术(锁消除、锁粗化)

### 底层同步机制

众所周知，`synchronized`使用时既可以修饰方法，也可以通过锁住指定对象来执行一段同步方法块：

1. 对于普通同步方法，比如`public synchronized int method()`，锁对象是该方法所属的**实例对象**

2. 对于静态同步方法，比如`public static synchronized int method()`，锁对象是该静态方法所属类的**Class对象**

如果某个线程试图访问同步代码块时，必须获取锁对象，在退出这段代码块或者抛出异常时，必须释放锁对象

### JVM实现Synchronized的具体方式

JVM是基于进入和退出`Monitor`对象来实现代码块同步和方法同步，但是具体细节有以下不同:

1. 同步代码块: 显示利用字节码指令`monitorenter`和`monitorexit`

2. 同步方法: `javac`编译器将该类编译成字节码时，在该方法对应的方法表中，将`access_flags`里启用`ACC_SYNCHRONIZED`修饰

   JVM调用同步方法时，相关的`invoke`方法指令会检查该方法是否具有`ACC_SYNCHRONIZED`标志，有的话会让执行线程获取对应的`monitor`对象(实例对象或者Class对象)，获取成功后才会执行方法体，退出方法后再释放该`monitor`对象。同步方法的执行期间，其他任何线程都无法再获取同一个`monitor`对象

JVM对同步方法的实现是隐式，无需通过显式的字节码指令完成。`monitorenter`和`monitorexit`是利用操作系统提供的互斥原语`mutex`实现，获取不到`monitor`对象的线程会被阻塞，从而被挂起等待被唤醒，会导致"用户态"和"内核态"之间的来回切换，由于线程上下文的切换，消耗的资源较多对性能影响较大

以下代码包含一个简单的同步代码块和一个同步方法:

```java
public class SynchronizedExample {

    public void method() {
        synchronized (SynchronizedExample.class) {
            System.out.println("我是同步代码块");
        }
    }

    public synchronized void synchronizedMethod() {
        System.out.println("我是同步方法");
    }
}
```

利用jclasslib查看这个类的字节码，以下是`SynchronizedExample::method`里的同步代码块对应的字节码:

![同步代码块](https://s2.loli.net/2023/04/14/T9EsAFtOcjgLfyQ.png)

然后是同步方法`SynchronizedExample::synchronizedMethod`对应的方法标志和字节码:

![同步方法-标志](https://s2.loli.net/2023/04/14/KoyM571HvTjaD8U.png)

![同步方法-字节码](https://s2.loli.net/2023/04/14/2ye7Pk8tBGubEVj.png)

### JVM如何处理锁对象

`synchronized`的实现最终还是要获取对应的`monitor`对象，所以JVM在堆中存储实例对象时，为了实现`synchronized`，在对象头中的Mark Word标记字段中添加了该对象作为锁对象的相关状态数据，如下图所示

![MarkWord-64bit](https://s2.loli.net/2023/04/15/yBWuSh9zNZdiH85.png)

JVM规范中，对象头里标志该对象当前状态的`tag bits`只有2bit，所以对于无锁态和偏向锁状态还需要额外的 1 bit 的标志位

### 锁升级过程

> 自*JDK1.6*引入偏向锁以来，距偏向锁设置为默认打开状态已经过去了很长一段时间，实际上在2019年12月，[JEP 374](https://openjdk.org/jeps/374)宣告要移除偏向锁，从*JDK15*开始不再默认使用偏向锁

JVM在**开启偏向锁**的情况下，创建一个新的对象时，对象初始就处于**可偏向但未偏向**的状态，Mark Word值赋为`0x05`，即`thread ID`、`epoch`和`age`都为0，且`是否偏向`标志位和`锁标志位`为`1 01`状态，锁状态的转换流程如下图所示:

![可偏向但未偏向-锁状态转换流程](https://s2.loli.net/2023/04/16/H9crlBvX6eOoPIM.png)

从偏向锁撤销偏向转到无锁态后，锁对象无法再进入偏向锁状态，其他线程下次想要获得该锁对象时只能获取轻量级锁

> 如果没有开启偏向锁，新对象创建时初始处于无锁态，Mark Word值赋为`0x01`，即`hashcode`、`age`为0，后3位标志位为`0 01`

#### 无锁态/偏向锁

当一个线程(下文称之为"本线程")进入同步代码块时，如果对应的同步对象没有处于轻量锁或重量级锁状态(即`tag bits`为`01`，对应无锁态或偏向锁状态)，查看对应的`biasable`这个1 bit标志位是否为1:

- **对象处于可偏向但未偏向的初始状态(`1 01`，线程ID字段为0)**: 使用CAS操作将锁对象Mark Word中的线程ID字段设置为本线程的ID
  
  1. CAS操作成功，则获取锁对象成功，此时对象处于偏向锁状态(`1 01`)

  2. CAS操作失败，说明有其他线程刚刚获得了该偏向锁(被设置成了其他线程的ID)，则进行**锁升级**，先撤销偏向锁(**Revoke Bias**)再进入下一轻量锁阶段

- **对象已处于偏向锁状态(`1 01`，线程ID字段不为0)**: 判断锁对象Mark Word线程ID对应的线程

  1. Mark Word 中的线程ID是本线程的ID，说明上次获取锁对象的线程就是自己，不需要再做任何其他获取锁的同步操作，对性能消耗很小

  2. Mark Word 中的线程ID不是本线程的ID，显然是本线程与其他线程出现了竞争，此时对应的锁对象要进入**锁升级**流程，因为它已经处于偏向锁状态了，先进行偏向锁的撤销才能进入下一轻量锁阶段

- **对象处于无锁状态(`0 01`)**: 由于无锁态无法再回到偏向锁状态，对应锁对象只能升级到轻量级锁状态，并由本线程获取该轻量级锁

从上面的流程可以找到，进入下一轻量锁阶段前，处于偏向锁状态的锁对象需要执行**撤销偏向**:

> 偏向锁撤销源码见`biasedLocking.cpp`中的[revoke_bias()](https://hg.openjdk.org/jdk8u/jdk8u/hotspot/file/574c3b0cf3e5/src/share/vm/runtime/biasedLocking.cpp#l146)方法

- 锁对象是**无锁态(`0 01`)**，不需要撤销

- 锁对象是偏向锁状态，根据Mark Word里的线程ID找到偏向锁的对应线程:
  
  1. 偏向锁的对应线程已死亡:

     - 不允许重偏向`allow_rebias == false`时，锁对象进入无锁态，当前线程再去获取该锁对象的轻量级锁

     - 允许重偏向时，将锁对象退回到**可偏向但未偏向**的初始状态，也就是把处于偏向锁状态锁对象的Mark Word里的线程ID重新置为0

  2. 偏向锁的对应线程仍然在运行中:

     - 对应线程**仍然拥有该锁对象**时(既可能是当前请求锁的线程也可能是其他已持有锁的线程)，将该锁对象升级为轻量锁，将Mark Word复制到对应线程正在执行栈帧中的Lock Record.Displaced Mark Word处

     - 对应线程**不再拥有该锁对象**时，与对应线程死亡时的做法一致:

       - 不允许重偏向时，锁对象进入无锁态

       - 允许重偏向时，将锁对象退回到**可偏向但未偏向**的初始状态

#### 轻量级锁

之所以称为"轻量级"，是因为获取该锁时仅需要CAS操作，而不需要调用操作系统的"重量级"互斥量

JVM中，线程虚拟机栈的每个栈帧中有一块称为**Lock Record**的空间，专门用来存储锁对象的Mark Word，Lock Record由两部分组成，主要是为了与锁对象的Mark Word形成双向引用:

- **Displaced Mark Word**: 目标锁对象处于轻量级锁前置状态时(只能是无锁态)的Mark Word，由于锁对象升级为轻量锁后，该锁对象的Mark Word中前62 bit将会全部变为指向栈帧中Lock Record的指针，所以Displaced Mark Word拷贝了之前的锁对象状态，以待解锁时恢复锁对象状态

- **Owner**: 指向Lock Record对应的锁对象的指针，即Object Reference

OpenJDK实现的HotSpot VM中，Lock Record通过以下两个类`BasicObjectLock`和`BasicLock`实现:

```c++
// A BasicObjectLock associates a specific Java object with a BasicLock.
// It is currently embedded in an interpreter frame.
class BasicObjectLock {
  friend class VMStructs;
 private:
  BasicLock _lock; // 锁对象的Mark Word, must be double word aligned
  oop       _obj;  // 指向锁对象
};

class BasicLock {
 private:
  volatile markOop _displaced_header;
};
```

**轻量级锁的加锁**:

上一节中可知，当前线程获取偏向锁失败时或者锁对象已处于无锁态时，需要获取对应的轻量级锁

下图是线程还未获得轻量级锁时，栈帧和锁对象的状态:

![Lock Record 1](https://s2.loli.net/2023/04/16/RIpfvyPETnZGKz2.png)

当前线程尝试用CAS将锁对象的Mark Word替换为指向Lock Record的指针(`ptr_to_lock_record`)：

- CAS操作成功，当前线程成功获取该轻量级锁，锁对象与栈帧的Lock Record之间双向引用，如下图所示:

  ![Lock Record 2](https://s2.loli.net/2023/04/16/hQdPKmMAnwTJp72.png)

- CAS操作失败，说明有其他线程修改了该锁对象的Mark Word，获取该锁对象的Mark Record，进行下列判断:

  1. 如果`ptr_to_lock_record`指向的是当前线程自己的栈帧中的Lock Record，说明是**当前线程自己执行了`synchronized`锁重入**，在栈帧中再压入一条`Displaced Mark Word`为`null`(全0)的Lock Record记录(其中的`Owner`部分仍然指向该锁对象)，整体保持栈的FILO特性，如下图所示:

     ![Lock Record 3](https://s2.loli.net/2023/04/16/2dpomjCP5GRFrsD.png)

  2. 如果`ptr_to_lock_record`指向的是其他线程的Lock Record，说明当前线程正在与其他线程争用该锁对象，当前线程开始**自旋CAS以获取该锁对象**，当自旋次数超过阈值`threshold`后，说明一直存在竞争所以需要将该轻量级锁膨胀为重量级锁(**inflate**)

**轻量级锁的解锁**:

由上述加锁过程可知，每当退出一层`synchronized`代码块时就要进行解锁，取出当前线程栈帧的最顶部Lock Record:

> 解锁过程源码见`synchronizer.cpp`中的[ObjectSynchronizer::fast_exit()](https://hg.openjdk.org/jdk8u/jdk8u/hotspot/file/87ee5ee27509/src/share/vm/runtime/synchronizer.cpp#l183)方法

- 如果`Displaced Mark Word`为null，说明要退出的同步代码块是重入的，移除这条Lock Record

- 如果`Displaced Mark Word`不为0，说明此时要从轻量级锁解锁返回到无锁态，利用CAS操作将`Displaced Mark Word`恢复给锁对象:

  1. CAS成功，轻量级锁解锁成功，锁对象恢复到无锁态

  2. CAS失败，说明有其他线程正在竞争该锁对象，将该锁对象膨胀为重量级锁(如果锁对象已处于重量级锁状态，执行膨胀的话会直接返回对应的`monitor`对象，详见下一节)后再进入重量级锁的解锁流程(`fast_exit()`方法中的最后一行`ObjectSynchronizer::inflate(THREAD, object)->exit (true, THREAD)`)

#### 重量级锁

重量级锁的实现离不开`monitor`对象，HotSpot VM通过`ObjectMonitor`这个类实现了`monitor`对象:

```c++
ObjectMonitor() {
    _header       = NULL;   //是一个markOop类型，markOop就是对象头中的Mark Word
    _count        = 0;      //抢占该锁的线程数 约等于 WaitSet.size + EntryList.size
    _waiters      = 0,      //等待线程数
    _recursions   = 0;      //锁重入次数
    _object       = NULL;   //ObjectMonitor寄生的锁对象
    _owner        = NULL;   //指向获得ObjectMonitor对象的线程或BasicLock
    _WaitSet      = NULL;   //处于WAITING状态的线程，加入到_WaitSet中
    _WaitSetLock  = 0 ;     //保护WaitSet的一个自旋锁(monitor大锁里面的一个小锁，这个小锁用来保护_WaitSet更改)
    _Responsible  = NULL ;
    _succ         = NULL ;  //当锁被前一个线程释放，会指定一个继承者线程，但是它不一定最终获得锁。
    _cxq          = NULL ;  //ContentionList 
    FreeNext      = NULL ;
    _EntryList    = NULL ;  //处于等待锁的BLOCKED状态的线程，即未获取锁被阻塞或者被wait的线程重新被放入entryList中
    _SpinFreq     = 0 ;     // 自旋频率
    _SpinClock    = 0 ;
    OwnerIsThread = 0 ;     //当前owner是thread还是BasicLock
    _previous_owner_tid = 0;//当前owner的线程id
}
```

`ObjectMonitor`中有两个队列`_WaitSet`和`_EntryList`，用以保存`ObjectWaiter`对象(每个因为得不到锁而阻塞的线程都会被封装为`ObjectWaiter`)，`_owner`指向当前持有该`monitor`对象的线程

- `_WaitSet`保存处于`WAITING`无限期等待状态的线程，该状态由正在运行的持有`monitor`的线程主动调用`Object.wait()`方法而产生，释放持有的`monitor`，将`_owner`置为null，`_count`自减，同时将该线程加入`_WaitSet`集合中等待**被主动唤醒**

- `_EntryList`保存处于`BLOCKED`阻塞状态的线程，当前线程获取处于轻量级锁或者重量级锁状态的锁对象失败时，将自己加入`_EntryList`中并进入阻塞状态

结合轻量级锁膨胀到重量级锁的过程，就可以理解`monitor`的作用，由上一节可知对轻量级锁加锁和解锁时都有可能触发锁膨胀

假设`Thread-0`已持有处于轻量级锁状态的锁对象，`Thread-1`想要获取该轻量级锁:

![Lock Record 4](https://s2.loli.net/2023/04/16/AMEqmKvV4w25Qul.png)

`Thread-1`无法通过CAS获取该轻量级锁，自旋次数超过阈值后，将锁对象膨胀为重量级锁:

- JVM为锁对象创建`Monitor`对象，锁对象的Mark Word的前62 bit存放指向重量级锁的指针`ptr_to_heavyweight_monitor`，后2bit的`tag bits`设为`10`

- 当前获取不到锁对象的线程`Thread-1`进入阻塞状态后加入`Monitor`的`EntryList`中

![Lock Record 5](https://s2.loli.net/2023/04/16/3DZvnkTBMIuVbqr.png)

由于`Thread-0`的Lock Record中存放的是锁对象处于无锁态的Mark Word，`Thread-0`退出同步代码块(对应字节码`monitorexit`)进行它认知角度上的解锁流程(认为自己持有的是轻量级锁)，尝试CAS将Mark Word的值恢复到锁对象中。由于预期值本应该是`Thread-0`的线程ID，但是锁对象已经升级为重量级锁状态，前62bit已从`ptr_to_lock_record`变化为`ptr_to_heavyweight_monitor`，所以CAS失败

接下来只能执行重量级锁的解锁，根据锁对象Mark Word中指向`Monitor`的指针找到`Monitor`对象，将其中的`Owner`字段设置为null，表示锁对象的持有者`Thread-0`释放了该`Monitor`对象，唤醒`EntryList`中第一个处于阻塞状态的线程，成为新的`Owner`

当`Monitor`的`EntryList`和`WaitSet`中不存在任何等待的线程时，说明不再有线程需要该锁对象，销毁该`Monitor`对象并将锁对象**退回到无锁态**，即锁膨胀为重量锁后就再也不能退回到轻量锁

重量级锁也是可重入的，当线程再次请求已持有的相同锁对象时，发现对应的`Monitor`对象的`Owner`就是本身，所以让计数器`_recursions`自增

> 什么时候会出现重入呢？比如在同步代码块中(锁对象是实例对象自身)调用实例对象的`synchronized`方法

```java
public class ReentrantSynchronized implements Runnable {
    
    static int i = 0;

    @Override
    public void run() {
        // this即实例对象自身
        synchronized (this) {
            for (int k = 0; k < Integer.MAX_VALUE; k++) {
                this.increase();
            }
        }
    }

    public synchronized void increase() {
        ++i;
    }
}
```

`WaitSet`和`EntryList`中的线程，其进入到阻塞状态时会调用操作系统的互斥量完成，比如Linux下使用`pthread_mutex_lock`函数

**synchronized的其他相关事项**:

- 在字节码的方法表中，如果子类没有重写父类的方法，那么子类的方法表中仍然会有父类方法，所以子类可以通过可重入锁`synchronized`调用父类的同步方法

- 由于`wait()`方法是在线程作为某个`Monitor`的`Owner`时才能够进入`WAITING`状态从而加入到`Monitor`的`WaitSet`中等待被主动唤醒，对应的`notify()/notifyAll()`方法将会唤醒锁对象对应的`WAITING`状态线程，即，从`WaitSet`中将对应的线程取出并加入到`EntryList`中

  这也说明了**为什么`wait()`、`notify()/notifyAll()`方法只能在同步代码块或同步方法中使用的原因**，必须让调用这些方法的锁对象处于能够获取`Monitor`对象的环境中

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

首先要说明的是，ReentrantLock实现了`java.uti.concurrent.locks.Lock`接口，Lock接口为J.U.C的显式锁定义了共性方法，即:

```java
void lock();  // 阻塞模式抢占锁，未抢占到时当前线程会一直阻塞

void lockInterruptibly(); // 可中断模式抢占锁，阻塞过程中能够接收中断信号中断当前线程

boolean tryLock();  // 非阻塞模式抢占锁，直接返回抢占锁的结果

boolean tryLock(Long time, TimeUnit unit);  // 在tryLock()基础上，限制抢占锁的时间限制(在时间限制里一直阻塞以抢占到锁)，超出时间后立刻返回结果

void unlock();  // 释放当前线程抢占到的锁

Condition newCondition(); // 创建与当前线程绑定的Condition条件，用于线程间"等待-通知"方式的通信
```

Lock锁弥补了JVM内置锁`synchronized`的不足，支持中断响应、超时、非阻塞抢占，且通过多个与锁绑定的Condition对象，实现更精细的等待唤醒控制。(`synchronized`代码块中只能对唯一的锁对象调用`wait`、`notify`等方法)

ReentrantLock是最常用的Lock实现，基于AQS实现了Lock接口定义的方法

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

### await()、signal()、signalAll()

与`synchronized`不同的是，持有ReentrantLock锁的线程想要进入无限期等待(WAITING)状态和限期等待(TIMED_WAITING)状态，是通过调用与Lock锁绑定的Condition对象的`await()`等方法实现的(底层调用了`LockSupport.park()`方法)

由于`synchronized`处理的是一个单一的锁对象，JVM实现`synchronized`是通过将锁对象关联到一个Monitor对象，而后者具有两个队列`_EntryList`和`_WaitSet`分别保存因获取不到锁而阻塞(BLOCKED)的线程和持有锁时主动调用`wait()`进入等待状态(包括限期等待与无限期等待)的线程

ReentrantLock优化了这个缺点，由Condition对象内部维护一个存储等待状态线程的双向队列，一个Lock锁可以创建多个ConditionObject，自然可以拥有多个等待队列，实现更全面、精细的"等待-通知"线程通信机制

`signal()`/`signalAll()`方法对标`notify()`/`notifyAll()`方法，前两者的源码中其实调用的是`LockSupport.unpark(Thread)`方法，唤醒被调用的条件对象ConditionObject维护的等待队列中的线程

```java
// in java.util.concurrent.locks.AbstractQueuedSynchronizer::ConditionObject.class
private void doSignal(ConditionNode first, boolean all) {
    while (first != null) {
        ConditionNode next = first.nextWaiter;
        if ((firstWaiter = next) == null)
            lastWaiter = null;
        if ((first.getAndUnsetStatus(COND) & COND) != 0) {
            enqueue(first);
            if (!all)
                break;
        }
        first = next;
    }
}

final void enqueue(Node node) {
        if (node != null) {
            for (;;) {
                Node t = tail;
                node.setPrevRelaxed(t);        // avoid unnecessary fence
                if (t == null)                 // initialize
                    tryInitializeHead();
                else if (casTail(t, node)) {
                    t.next = node;
                    if (t.status < 0)          // wake up to clean link
                        LockSupport.unpark(node.waiter);
                    break;
                }
            }
        }
    }

```

## 死锁原因与避免

Java中如果出现死锁，其4个充分必要条件如下：

1. **互斥**: 一个资源每次只能被一个线程使用，多个线程不能同时使用同一个资源

2. **持有并等待**: 一个线程在阻塞等待某个资源，而该线程在等待该资源的同时始终不释放自己已经持有的资源

3. **无法剥夺**: 一个线程已经获得的资源，在该线程未使用完之前，其他线程无法强行剥夺该资源

4. **环路等待**: 若干线程形成头尾相接的环路资源等待关系

要避免死锁的发生，只需要破坏以上4个条件中的任意一个即可，但是在并发环境中，前3个条件是锁必须具备的条件。所以在实际的Java并发编程中，要避免死锁最常见且最具可行性的方法就是使用资源有序分配法，去破坏线程的环路等待关系

一般而言，实际开发中要注意:

1. 加锁顺序: 每个线程对同一批资源进行竞争时，保证加锁顺序相同(这样就不会出现你持有我需要的锁，我持有你需要的锁这样的死循环)

2. 加锁时限: 针对锁设置一个超时时间，如果超过该时间还没有获取到锁，则终止本次对资源的竞争，释放之前得到的所有锁

3. 死锁检查: 这是死锁避免的预防机制，可以用`jstack`等工具检测JVM中是否出现死锁，就可以溯源并解决

### 死锁预防

预防死锁就是要破坏死锁产生的4个必要条件，一般来说除了互斥条件外，破坏其他三个条件是常用的做法:

1. **破坏持有并等待条件**: 线程在获取其需要的资源时，一次性全部获取，

2. **破坏无法剥夺条件**: 已经占用了部分资源的线程，在进一步申请其他资源时，如果申请不到，可以主动释放当前已占用的资源，避免其他线程申请不到本线程已经占用的资源

3. **破坏环路等待条件**: 各个线程都按照某一相同顺序申请资源，释放资源时按照FILO的顺序反序释放，这样就能够破坏线程间的环路等待关系(即**资源有序分配法**，这也是死锁避免最常用的方法，见下一节具体解释)

### 死锁避免

避免死锁就是在分配资源时，借助于算法(比如银行家算法)对资源分配进行预评估，保证资源分配后能够使各个线程进入安全状态，而不会出现死锁

前面提到，避免死锁最常见且最具可行性的方法就是使用**资源有序分配法**，破坏第四个必要条件——环路等待条件

资源有序分配法即，各个线程总是以相同的顺序去获取自己需要的资源，释放资源时也是反序逐个释放。比如，线程A先尝试获取资源1，然后再获取资源2，另一个线程B尝试获取资源的顺序也是如此，这样就不可能出现环路等待情况，破坏了环路等待条件，避免了死锁

### 死锁检测

1. 利用`jstack`工具，它是JDK自带的线程堆栈分析工具

   首先使用`jps -l`查看Java进程的编号，然后利用`jstack <process_id>`查看对应Java进程的信息

   `jstack`会给出该进程的分析信息，可以看到进程内各个线程的状态，比如`BLOCKED`、`WAITED`等。`jstack`还会检测该JVM进程内是否存在死锁，会提示`Found one Java-level deadlock`，尔后会列出产生该死锁的相关线程以及它们无法申请到的具体资源(锁对象)

2. 使用图形化工具`jconsole.exe`，选择指定JVM进程后，点击检测死锁即可查看存在死锁的线程

3. 使用图形化工具`jvisualvm.exe`，操作过程与`jconsole`类似
