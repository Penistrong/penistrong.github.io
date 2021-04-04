---
layout:     post
title:      "[推荐系统]Embedding"
subtitle:   "Subtitle here"
author:     Penistrong
date:       2021-03-30 19:25:23 +0800
categories: jekyll update
catalog:    true
mathjax:    false
katex:      true
tags:
    - 毕业设计
    - RecSys
    - DeepLearning
---

# 推荐系统
## Embedding
Embedding是用一个数值向量表示一个对象的方法，这个对象可以是一个词、一个物品也可以是一部电影。之所以能用向量表示物品，是因为这个向量与其他物品向量之间的距离可以反映这些物品的相似性，即两个向量间的距离向量可以反映他们之间的关系。

Google的著名论文Word2vec中提出了Embedding的经典方法，利用Word2vec模型将单词映射到高维空间中。词向量之间的运算可以揭示词之间的关系，比如:

$$ Embedding(Woman) = Embedding(Man) + [Embedding(Queen) - Embedding(King)] $$

即从man到woman的向量和从king到queen的向量，在高维空间中其方向和尺度都异常接近。

那么推荐系统中何以用到Embedding技术呢？既然Embedding技术可以揭示向量之间的关系，那么在电影推荐系统中，如果将电影和用户映射到Embedding空间后，就可以通过找出某一用户周围的电影向量，将这些电影推荐给用户即可。

### Embedding技术在特征工程中的重要性
#### 处理稀疏特征
在传统特征工程中，因为推荐场景下的类别、ID类特征尤其多，大量使用One-hot编码会导致样本特征向量极度稀疏，而深度学习的结构特点又不利于稀疏特征向量的处理，因此较为成熟的深度学习推荐模型都会使用Embedding层将稀疏高维特征向量转换为稠密低维特征向量。

#### 融合基本特征
从上述对Embedding的介绍中可以发现，相比由原始信息直接处理得到的特征向量，Embedding的表达能力更强。Embedding几乎可以引入任何信息进行编码，使其本身融合大量的信息，即Embedding技术是一种可以通过融合大量基本特征从而生成高阶特征向量的有效手段。

### Word2vec

Google的Word2vec即“word to vector”，即将词表达为向量。

想要训练Word2vec模型，需要准备由一组句子组成的语料库。假设一个长度为T的句子其包含的词为$w_1,w_2,...,w_t$，假定每个词都与其相邻词关系最密切。

Word2vec将模型分为两种形式：

#### CBOW

CBOW模型假设句子中每个词的选取都由相邻的词来决定，即CBOW模型的输入是$w_t$周边的词（不含$w_t$），预测输出则为$w_t$。

#### Skip-gram

Skip-gram模型与CBOW模型相反，它鸡舍句子中的每个词都决定了相邻词的选取。该模型中的输入是$w_t$，而预测输出则为w~t~周边的词。Skip-gram模型通常更适用于推荐系统，因为为某个用户生成推荐列表时往往只有用户某一特征向量作为输入，要根据该向量找到其周边的向量。

![Word2vec的两种模型结构CBOW和Skip-gram](https://static001.geekbang.org/resource/image/f2/8a/f28a06f57e4aeb5f826df466cbe6288a.jpeg)

#### 生成Word2vec样本

Word2vec最初应用于NLP领域，训练样本来自于语料库。

**样本生成方法:** 从语料库中抽取一个句子，选取一个长度为$2c+1$的滑动窗口，将该窗口在句子上从左向右滑动，中心词每改变一次，这个滑动窗口中的词组就形成了一个训练样本。在Skip-gram模型中，中心词决定了其相邻词，则该训练样本定义了输入与输出。
例子：

$$  
    \color{red}Embedding \color{black}| \color{red}技术 \color{black}|在| \color{red}深度学习 \color{black}| \color{red}推荐系统 \color{black}|中|的|\color{red}可用性 \\ 
    \color{black}去除介词和分词 \\
    选取大小为3的滑动窗口在该句子上滑动，生成适用于Skip-gram模型的训练样本 \\
    \begin{alignedat}{2}
    Sample1: & 技术 & \to & Embedding,深度学习 \\
    Sample2: & 深度学习 & \to & 技术,推荐系统 \\
    Sample3: & 推荐系统 & \to &深度学习,可用性
    \end{alignedat}
$$

#### Word2vec的模型结构

根据Google论文中的Word2vec模型结构，可以发现其本质是一个三层的神经网络。

![Word2vec模型结构](https://static001.geekbang.org/resource/image/99/39/9997c61588223af2e8c0b9b2b8e77139.jpeg)

输入层与输出层的维度都是语料库词典大小V。使用上一节中生成的训练样本，这里的输入层就是将中心词转换为One-hot编码后的特征向量作为输入，输出层则输出相邻词转换为Multi-hot编码的特征向量。即基于Skip-gram的Word2vec解决的是一个多分类问题。

中间的隐含层维度为N，N即调参大师负责的工作。炼丹大师需要对模型的效果和复杂度进行权衡，且最终每个词其对应的Embedding向量的维度也由N来决定。

注意隐含层没有使用激活函数，输出层采用Softmax作为激活函数。

这个神经网络最终是要表达从输入向量到输出向量的一个条件概率关系：

$$ p(w_O \mid w_I) = \frac{exp(v'_{w_O}v_{w_I})}{\sum_{i=1}^{V}exp(v_{w_i}^{'\top}v_{w_I})}  $$

使用极大似然估计最大化该条件概率，能够让相似的词向量的内积距离更接近。损失函数与梯度下降另见博文（等我开始学花书再写蛤蛤）。

#### 提取词对应的Embedding向量

上一节中描述了Word2vec的神经网络，那么如何提取每个词对应的Embedding向量呢？前面提到的维度为N的隐含层，这个N其实就是Embedding向量的维度

![](https://static001.geekbang.org/resource/image/0d/72/0de188f4b564de8076cf13ba6ff87872.jpeg)

上图中的Embedding Matrix即输入向量矩阵$W_{V \times N}$，该矩阵的每一个行向量就是目标词向量。比如语料库词典中第i个词对应的Embedding，其输入向量由于采用One-hot编码，该输入向量的第i维就应该是1，则$W_{V \times N}$中第i行的行向量就是第i个词对应的Embedding。

应用于推荐系统中时，可以把输入向量矩阵转换成词向量查找表。比如当$V=10000 \space N=300$时，权重矩阵$W_{V \times N}$为10000 X 300维，将其转换为词向量查找表后，每行的权重成为对应词的Embedding向量。将该查找表存储到推荐系统使用的线上数据库中，就可以在计算推荐列表的过程中快速使用Embedding去计算相似性等重要特征。

### Item2Vec

NLP领域的Word2vec处理的是句子中的词“序列”，如果将用户观看电影的行为记录作为一个“序列”，根据Word2vec训练的原理，这种序列也可以使用Embedding技术。微软于2015年提出Item2Vec方法，推广Word2vec，使Embedding方法适用于几乎所有的序列数据，不同的地方只在于要使用“序列”的形式将要表达的对象表示出来，仿佛成了一个“句子”，再将其输入Word2vec模型，就可以得到该序列中任一物品的Embedding向量。

对于推荐系统而言，Item2Vec可以利用物品的Embedding直接求得它们的相似性，或者将其作为特征输入推荐模型进行训练。

## 应用Embedding
