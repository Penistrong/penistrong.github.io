---
layout:     post
title:      "[jekyll博客搭建]模板js渲染与服务器主动渲染"
subtitle:   "在博客中渲染LaTex的血泪史"
author:     Penistrong
date:       2021-03-08 18:17:38 +0800
categories: jekyll update
catalog:    true
mathjax:    false
katex:      true
tags:
    - blog
    - LaTex
    - jekyll
---

## 前言

作为一名从事CS行业的学生(24岁，是学生！)，搭建一个博客记录自己的学习过程是刚需。
在浏览了一圈建博教程之后，彼时尚没有服务器的我选择了GitHub Pages作为自己的博客第一站，使用jekyll作为静态博客网站生成器并使用GithubPages托管。
利用jekyll的架构和其他成熟博客的模板，很轻松便能搭建[个人博客](https://penistrong.github.io)。
通过编写Markdown文件并在文件头设置相关变量，就可利用jekyll的Liquid语法进行模板拼接和网页渲染。

## 血泪史
### 配置过程

- 在博客的初始阶段于本地构建jekyll服务调试后发布到git仓库。$So \space easy$

    ```shell
    gem install bundler jekyll # jekyll 4.2.0;bundler 3.1.2
    bundler install
    jekyll serve --watch
    ```

- 过了一段时间，由于GFW的封锁，我不得不将搭载v2ray服务端的VPS使用TLS+WebSocket+Nginx进行改造，伪装网站流量。在一系列注册域名、设置dns解析、配置Nginx等等操作后，我突然萌生了一个想法：为什么不将VPS作为服务器部署自己的个人博客呢？而且这很容易做到，只需要在服务器端安装Ruby和jekyll，在服务端运行即可。于是我在VPS上git-clone了自己的penistrong.github.io.git仓库，安装依赖并配置Nginx后成功运行。
    - 使用`jekyll build`。将静态网站生成至服务器的域名网站目录下，使用增量更新，力求快速。

    ```shell
    nohup jekyll build --source /usr/workspace/penistrong.github.io --destination /www/wwwroot/www.penistrong.top/blog_site --incremental --watch
    ```

    - 配置Nginx。

    ```nginx
    location /blog {
        alias /www/wwwroot/www.penistrong.top/blog_site;
    }
    ```
    
    - 由于html中各文件的链接通过` file_path | prepend site.baseurl `拼接而成。注意在jekyll的`_config.yml`中的`baseurl`指定的是自己博客在网站下的子目录。由于github.io的主页就是博客，在github.io里`baseurl = ""`，在VPS上因为还要部署其他应用，因此使用`/blog`作为subpath，即`baseurl="/blog"`。

    ```yaml
    # penistrong.github.io _config.yml
    baseurl: "" # the subpath of your site, e.g. /blog.On VPS there is "/blog" while "" in penistrong.github.io
    url: "penistrong.github.io" # the base hostname & protocol for your site, e.g. http://example.com

    # www.penistrong.top _config.yml
    baseurl: "/blog" # the subpath of your site, e.g. /blog.On VPS there is "/blog" while "" in penistrong.github.io
    url: "www.penistrong.top" # the base hostname & protocol for your site, e.g. http://example.com 
    ```

- 在VPS上部署成功后，我就写了一篇包含数学推导的博文，使用了$LaTex$语法。但是这个时候就需要引入渲染LaTex的概念。由于是jekyll新手，我只是在官方文档中寻找是否有相关教程。查阅后得知可以通过安装jekyll-spaceship，即一款包含mathjax、emoji渲染器的jekyll plugin，在jekyll开启服务时可以渲染博文中的LaTex语法块为html代码块。当时比较仓促，**忘记查阅GitHub Page是否支持**，只是编写LaTex，运行jekyll服务进行渲染。在VPS上显示很正常。
    - 安装`jekyll-spaceship`

    ```shell
    gem install jekyll-spaceship # jekyll-spaceship-0.9.8
    ```

    - 配置`_config.yml`

    ```shell
    # Plugins
    # jekyll 4.2.0
    plugins:
        - jekyll-feed
        - jekyll-paginate   # If you use bundle to run jekyll, don't forget append [gem "jekyll-paginate", "~> 1.1.0"] in GemFile
        - jekyll-spaceship  # For MathJax rendering
    ```

    - 配置`GemFile`

    ```shell
    # If you have any plugins, put them here!
    group :jekyll_plugins do
        gem "jekyll-feed", "~> 0.12"
        gem "jekyll-paginate", "~> 1.1.0"
        gem "jekyll-spaceship", "~> 0.9.8"
    end
    ```

---

### 问题描述

- **问题伊始**：VPS上效果不错，可是penistrong.github.io该怎么办呢，GitHubPages似乎并不能读取GemFile中的相关配置，也就是说在github的个人博客上LaTex仍然无法渲染。于是想利用页内渲染方法，引入支持渲染LaTex的相关js插件完成诉求。

- 页内LaTex的渲染是通过引入[MathJax@v3](http://docs.mathjax.org/en/latest/index.html)实现的，在需要渲染的`博客.md`文件头中设置变量 `mathjax = true`。通过_layouts/post.html中的 `{% if page.mathjax %} {% endif %}` 代码块引入MathJax插件渲染页面。
    ```html
    <!-- MathJax v3 in mathjax_support.html -->
    <script>
    MathJax = {
        tex: {
            inlineMath: [['$', '$'], ['\\(', '\\)']],
            displayMath: [['$$', '$$'], ['\\[', '\\]']],
            processEscapes: true,
        },
        svg: {
            fontCache: 'global'
        }
    };
    </script>
    <script src="https://polyfill.io/v3/polyfill.min.js?features=es6"></script>
    <script type="text/javascript" id="MathJax-script" async
            src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js">
    </script>
    ```
    $inlineMath$即行内数学公式，使用常用的单dollar进行包裹。
    $displayMath$即块级数学公式，使用双dollar包裹。

- 但是，在Github Pages中，块级LaTex表达式并没有被正确识别，公式顶格、错位等现象时有发生。在生成的页面中寻找

