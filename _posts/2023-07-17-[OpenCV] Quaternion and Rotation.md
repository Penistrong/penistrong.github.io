---
layout:     post
title:      "[OpenCV] Quaternion and Rotation"
subtitle:   "四元数与3D旋转，Rodrigues Formula"
author:     Penistrong
date:       2023-07-18 14:30:41 +0800
categories: jekyll update
catalog:    true
mathjax:    false
katex:      true
tags:
    - OpenCV
---

# 四元数

## 四元数基本性质

对于两个四元数 $q_1=[s, \vec{v}]$ 和 $q_2=[t, \vec{u}]$，仿照向量它们有一些基础的代数性质

### 四元数乘法

四元数乘法不遵守交换律，即 $q_1q_2 \ne q_2q_1$，与张量类似，有了左乘与右乘的区别

#### 矩阵形式

#### $\textrm{Graßmann}$积

$$
q_1q_2 = [st - \vec{v} \cdot \vec{u}, s\vec{u} + t\vec{v} + \vec{v} \times \vec{u}]
$$

## 3D旋转公式

按照轴角(Axis Angle)旋转的定义，向量绕着旋转轴进行旋转

旋转前向量为 $\vec{v}$，旋转后向量为 $\vec{v'}$

$\vec{u}$ 是旋转轴Axis对应的单位旋转向量，$\theta$ 为向量 $\vec{v}$ 绕旋转向量 $\vec{u}$ 的旋转角

### 向量型: Rodrigues Formula

罗德里格斯公式直接以向量形式描述了三维空间中向量的旋转公式:

$$
\begin{equation}
\vec{v'} = \cos{\theta}\vec{v} + ( 1 - \cos{\theta})(\vec{u}\cdot\vec{v})\vec{u} + \sin{\theta}(\vec{u} \times \vec{v})
\end{equation}
$$

### 四元数型

$\vec{v}$ 和 $\vec{v'}$ 对应的纯四元数分别为 $v=[0,\vec{v}]$ 和 $v'=[0,\vec{v'}]$

利用一个单位四元数可以统一地表达向量的旋转:

$$
q = [\cos{\frac{\theta}{2}}, sin{\frac{\theta}{2}}\vec{u}]
$$

任意向量 $\vec{v}$ 沿着以单位向量 $\vec{u}$ 定义的旋转轴旋转 $\theta$ 度之后的$\vec{v'}$可以使用四元数乘法获得(向量扩展为纯四元数形式):

$$
\begin{equation}
v' = qvq^{*} = qvq^{-1}
\end{equation}
$$

### 四元数旋转公式与Rodrigues Formula的等价性

同为3D旋转公式，四元数型和向量型其实是完全等价的

对于式(2)，旋转后向量 $\vec{v'}$ 可以从向量形式扩充为对应的纯四元数形式 $v'$

$$
v' = qvq^{*} = [0, \vec{v'}]
$$

联系式(1)，应当有:

$$
\begin{equation}
qvq^{*} = [0, \cos{\theta}\vec{v} + ( 1 - \cos{\theta})(\vec{u}\cdot\vec{v})\vec{u} + \sin{\theta}(\vec{u} \times \vec{v})]
\end{equation}
$$

只需证明式(3)，即可说明二者的等价性:

$$
\begin{align*}
\textrm{LHS} &= qvq^{*} \\
             &= [\cos{\frac{\theta}{2}}, \sin{\frac{\theta}{2}}\vec{u}] [0, \vec{v}] [\cos{\frac{\theta}{2}}, -\sin{\frac{\theta}{2}}\vec{u}] \tag*{(\textrm{四元数乘法})} \\
             &= \left[-\sin{\frac{\theta}{2}}\vec{u} \cdot \vec{v}, \cos{\frac{\theta}{2}}\vec{v} + \sin{\frac{\theta}{2}}\vec{u} \times \vec{v} \right] \left[\cos{\frac{\theta}{2}}, -\sin{\frac{\theta}{2}}\vec{u} \right] \tag*{(\textrm{利用Graßmann积})} \\
\end{align*}
$$

分别计算上述式子中两个四元数乘积的实部和虚部:

$$
\begin{align*}
\Re &= -\sin{\frac{\theta}{2}}\cos{\frac{\theta}{2}}\vec{u} \cdot \vec{v} - \left( \cos{\frac{\theta}{2}}\vec{v} + \sin{\frac{\theta}{2}\vec{u} \times \vec{v}} \right) \cdot \left( -\sin{\frac{\theta}{2}}\vec{u} \right) \\
    &= -\sin{\frac{\theta}{2}}\cos{\frac{\theta}{2}}\vec{u} \cdot \vec{v} + \sin{\frac{\theta}{2}}\cos{\frac{\theta}{2}}\vec{u} \cdot \vec{v} + \sin^2{\frac{\theta}{2}}(\vec{u} \times \vec{v}) \cdot \vec{u} \\
    &\xlongequal{(\vec{u} \times \vec{v}) \cdot \vec{u} = 0} 0 \\[10px]
\Im &= \left( -\sin{\frac{\theta}{2}}\vec{u} \cdot \vec{v} \right) \left( -\sin{\frac{\theta}{2}}\vec{u} \right)
       +\cos{\frac{\theta}{2}} \left( \cos{\frac{\theta}{2}\vec{v}} + \sin{\frac{\theta}{2}}\vec{u} \times \vec{v} \right) \\
    & ~~~~ + \left( \cos{\frac{\theta}{2}}\vec{v} + \sin{\frac{\theta}{2}\vec{u} \times \vec{v}} \right) \times \left( -\sin{\frac{\theta}{2}}\vec{u} \right) \\
    &= \sin^2{\frac{\theta}{2}}(\vec{u} \cdot \vec{v})\vec{u} + \cos^2{\frac{\theta}{2}}\vec{v} + \sin{\frac{\theta}{2}}\cos{\frac{\theta}{2}}\vec{u} \times \vec{v} - \sin{\frac{\theta}{2}}\cos{\frac{\theta}{2}}\vec{v} \times \vec{u} \\
    & ~~~~ - \sin^2{\frac{\theta}{2}}(\vec{u} \times \vec{v}) \times \vec{u} \tag*{(\textrm{叉积反交换律})} \\
    &= \sin^2{\frac{\theta}{2}}(\vec{u} \cdot \vec{v})\vec{u} + \cos^2{\frac{\theta}{2}}\vec{v} + 2\sin{\frac{\theta}{2}}\cos{\frac{\theta}{2}}\vec{u} \times \vec{v} + \sin^2{\frac{\theta}{2}}\vec{u} \times (\vec{u} \times \vec{v}) \\
    &= \sin^2{\frac{\theta}{2}}(\vec{u} \cdot \vec{v})\vec{u} + \cos^2{\frac{\theta}{2}}\vec{v} + 2\sin{\frac{\theta}{2}}\cos{\frac{\theta}{2}}\vec{u} \times \vec{v} \\
    & ~~~~ + \sin^2{\frac{\theta}{2}}\left[ (\vec{u} \cdot \vec{v}) \cdot \vec{u} - (\vec{u} \cdot \vec{u}) \cdot \vec{v} \right] \tag*{(\textrm{矢量三重积})} \\
    &= 2\sin^2{\frac{\theta}{2}}(\vec{u} \cdot \vec{v})\vec{u} + 2\sin{\frac{\theta}{2}}\cos{\frac{\theta}{2}}(\vec{u} \times \vec{v}) + \left( \cos^2{\frac{\theta}{2}} - \sin^2{\frac{\theta}{2}} \right)\vec{v} \\
    &= \cos{\theta}\vec{v} + (1 - \cos{\theta})(\vec{u} \cdot \vec{v})\vec{u} + \sin{\theta}(\vec{u} \times \vec{v})
\end{align*}
$$

化简完实部与虚部后则有:

$$
\begin{align*}
\textrm{LHS} &= qvq^{*} \\
             &= \left[ \Re, \Im \right] \\
             &= \left[ 0, \cos{\theta}\vec{v} + (1 - \cos{\theta})(\vec{u} \cdot \vec{v})\vec{u} + \sin{\theta}(\vec{u} \times \vec{v}) \right] \\
             &= \textrm{RHS}
\end{align*}
$$

式(3)得证，充分说明了四元数型旋转公式与罗德里格斯公式的等价性，可见**对于计算机而言**利用四元数计算旋转后的向量要比直接使用罗德格里斯公式计算简洁得多
