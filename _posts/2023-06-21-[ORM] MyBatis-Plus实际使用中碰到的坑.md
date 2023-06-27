---
layout:     post
title:      "[ORM] MyBatis-Plus实际使用中碰到的坑"
subtitle:   "我永远喜欢Spring Data JPA"
author:     Penistrong
date:       2023-06-21 09:40:39 +0800
categories: jekyll update
catalog:    true
mathjax:    false
katex:      true
tags:
    - ORM
    - Java
---

# Mybatis-Plus

## 自动填充配置

### 字段自动填充没有生效

**S**:

> 实体类基类`BaseEntity`中的`updatedTime`字段明明标注了`fill=FieldFill.INSERT_UPDATE`, 按照字面含义是在插入和更新时自动更新该字段，而实际使用中却并没有自动更新

**T**:

定位MyBatis-Plus处理字段自动更新的逻辑，尝试解决该问题

**A**:
  
查询MyBatis-Plus文档的[自动填充功能](https://baomidou.com/pages/4c6bcf/)一节可知自动更新的原理如下:

- 在实体类上使用注解`@TableField(..., fill = FieldFill.xxx)`将对应字段标记为自动填充且可指定填充策略`FieldFill`

  ```java
  public enum FieldFill {
    DEFAULT,        // 默认不处理
    INSERT,         // 插入时填充字段
    UPDATE,         // 更新时填充字段
    INSERT_UPDATE   // 插入和更新时填充字段
  }
  ```

- 实现元对象处理接口: `com.baomidou.mybatisplus.core.handlers.MetaObjectHandler`

  ```java
  @Component
  public class CustomMetaObjectHandler implements MetaObjectHandler {

      @Override
      public void insertFill(MetaObject metaObject) {
          this.fillStrategy(metaObject, 'createdTime', LocalDateTime.now());
      }

      @Override
      public void updateFill(MetaObject metaObject) {
          this.strictUpdateFill(metaObject, "updatedTime", () -> LocalDateTime.now(), LocalDateTime.class);
      }
  }
  ```

  插入或更新时就会使用上述重写的方法进行实际填充
  
  1. 粒度较粗的情况下，使用`MetaObjectHandler`接口中的`fillStrategy()`方法即可

  2. 如果想要粒度更细(比如以字段类型+字段名区分不同字段的填充策略)则需要使用接口中的`strictInsertFill`和`strictUpdateFill`方法

     ```java
     // in interface: MetaObjectHandler 
     // The following method has 2 other overloading method 
     default <T, E extends T> MetaObjectHandler strictUpdateFill(MetaObject metaObject, String fieldName, Supplier<E> fieldVal, Class<T> fieldType) {
         return strictUpdateFill(findTableInfo(metaObject), metaObject, Collections.singletonList(StrictFill.of(fieldName, fieldVal, fieldType)));
     }
     ```

(*坑来了*)填充的原理是在插入或更新时由`MetaObjectHandler`实现类直接给对应的实体类**对象**`entity`设置属性值，如果无值则入库后必为`null`

`MetaObjectHandler`提供的默认策略为: **如果属性有值则不覆盖，如果填充值为`null`则不填充**

且在使用`IService`或`Mapper`中的`update(T t, Wrapper updateWrapper)`时，**如果实体类`t`为`null`，也会导致自动填充失效**

从上面的描述中可以看到，自动填充是对实际对象`entity`设置值，如果不存在实际的实体类对象，那么自动填充就会失败

按照MyBatis-Plus的CRUD接口部分文档所述:

> QueryWrapper(LambdaQueryWrapper) 和 UpdateWrapper(LambdaUpdateWrapper) 的父类用于生成 sql 的 where 条件, entity 属性也用于生成 sql 的 where 条件

**如果没有`entity`，`MetaObjectHandler`就无法在对应的`entity`中设置字段值，也就无法自动填充字段**

比如基于`LambdaUpdateWrapper`的**lambdaUpdate()**方法构造的更新条件，如果调用`this.baseMapper.update(T entity, Wrappers.<T>lambdaUpdate().eq().set())`时实体类对象`entity`传参`null`，由于不存在实体对象`entity`去构造SQL的WHERE子句，自动填充就会失效

另外，使用`LambdaUpdateChainWrapper`时通常都是利用链式调用在最后一步调用`.update()`方法，如果不给`entity`作为参数也会导致自动填充失效

#### 解决方法

分两种情况讨论:

1. **没有利用QueryWrapper查出数据表实体`entity`，直接使用`[Lambda]Update[Chain]Wrapper`进行操作**

   - 调用`this.update(T entity, Wrapper<T> updateWrapper)`: 第一个参数直接new一个`entity`空对象
  
     ```java
     this.update(new CameraInstance(),
                 Wrappers.lambdaUpdate()
                            .eq(CameraInstance::getId, "xxx")
                            .set(CameraInstance::getStatus, heartBeatStatusDto.getStatus()))
     ```

   - 调用`this.update(Wrapper<T> updateWrapper)`: 构造`updateWrapper`时new一个`entity`空对象传参，比如`Wrappers.update(entity)`或者`Wrappers.lambdaUpdate(entity)`

     ```java
     this.update(Wrappers.lambdaUpdate(new CameraInstance())
                            .eq(CameraInstance::getId, "xxx")
                            .set(CameraInstance::getStatus, heartBeatStatusDto.getStatus()))
     ```

   - 调用`this.lambdaUpdate()`构造链式条件构造器，在链式调用的最后调用`.update(T entity)`，new一个`entity`空对象传参即可

     ```java
     this.lambdaUpdate()
            .eq(CameraInstance::getInstanceId, heartBeatStatusDto.getInstanceId())
            .eq(CameraInstance::getGatewayId, heartBeatStatusDto.getGatewayId())
            .set(CameraInstance::getStatus, heartBeatStatusDto.getStatus())
            .update(new CameraInstance())
     ```

2. **已经使用QueryWrapper查出数据表实体`entity`，直接将`entity`作为`UpdateWrapper`的参数**

   与上面一种情况类似，直接将查出的数据表实体`entity`传入UpdateWrapper用于组装SQL时的WHERE子句条件生成(调用其他API构造的条件字段可以不去重)

## LambdaQuery/Update[Chain]Wrapper
