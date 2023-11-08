---
layout:     post
title:      "[Linux] Manjaro搞机备忘"
subtitle:   "Manjaro baed on archlinux"
author:     Penistrong
date:       2023-11-08 13:27:23 +0800
categories: jekyll update
catalog:    true
mathjax:    false
katex:      true
tags:
    - Linux
---

# Manjaro搞机备忘录

## 硬件外设

### 双屏配置

#### 单显卡双屏

1. [2022.11.17]已知`Quadro P1000`的miniDP口使用`miniDP转HDMI`线与直连的`miniDP转DP`同时作为输出，会导致各种奇怪的双屏问题，改用两根直连`miniDP转DP`线解决

2. [2023.02.10]实验室主机加装`Geforce RTX2070`后，将P1000作为输出双屏的显示卡(`GPU:1`)，2070作为深度学习计算卡(`GPU:0`)，详见[双显卡双屏](#双显卡双屏-todo)一节

#### 双显卡双屏-TODO

[2023.02.10]实验室主机加装`Geforce RTX2070`后，本意是想*让两块显卡各自负责一块屏幕的显示输出*，但是主板BIOS的`VGA Priority`选项限定死了PCI-E插槽的显示输出优先级，如下所示：

- PCH SLOT 1 [PCI-E 3.0x16]
- CPU SLOT 2 [PCI-E 3.0x8(IN 3.0x16)]
- CPU SLOT 4 [PCI-E 3.0x16]
- CPU SLOT 6 [PCI-E 3.0x16]

注意`超微X11SRA`主板的3根PCI-E全长插槽，最底下的插槽为`CPU SLOT 2`，倒序向上

安装在CPU SLOT 4上的2070被主板优先检测为`GPU:0`，安装在CPU SLOT 6上的P1000顺序检测为`GPU:1`，BIOS中的默认设置`VGA Priority=Auto`会导致主板仅检测`GPU:0`上的显示输出，更改为`VGA Priority=CPU SLOT 6`即可，但是这样就无法实现预想的工作负载，不得已将P1000作为双屏的显示输出，2070负责计算(不需要改动任何训练代码，比如Pytorch下仍使用`device:0`)

## 包管理器

### 切换Manjaro分支

在使用Manjaro时总是会碰到依赖库版本低于已安装软件包所需依赖的版本问题，这是因为软件源设置为了`archlinuxcn`，但是这个源是为arch设计的，打包时用的是arch的库版本，而Manjaro的`stable`分支相对于arch有明显的滞后，经常会出现库版本不一致而导致软件包无法使用的问题

```shell
# 以排查Mysqld.service无法正常启动为例
ldd /usr/bin/mysqld

# output
libicuuc.so.73 => not found
libicui18n.so.73 => not found
```

去archlinux.org搜索`libicuuc.so`，发现它属于依赖库`icu`，版本73.2-1，而Manjaro的`icu`版本还是72.1-2，很难受，而且不是每次都能靠直接从archlinux.org下载`.zst`包安装超前stable分支的版本

所以直接切换分支到`unstable`(或者不使用`archlinucn`作为软件源，但是国内你懂的，速度太慢了)

```shell
# 查看当前分支
sudo pacman-mirrors --get-branch

# 切换指定分支 有3个目标分支 stable testing unstable
sudo pacman-mirrors -api --set-branch {branchname}
sudo pacman -Syyu
```

#### 切换后碰到的问题

1. systemd报错`Special user nobody configured, this is not safe!`

   切换到unstable分支后使用的是新版systemd，安全限制更加严格，不再建议使用`User=nobody`权限运行守护进程

   使用新的安全规范替代即可:

   ```shell
   # Old Version
   User=nobody
   # New Version
   DynamicUser=yes
   ```

### 未及时更新导致内核EOL

较长的一段时间里没有使用Manjaro，当前使用的内核被标记为EOL，导致无法更新软件包，提示各种冲突

由于Manjaro滚动更新的特性，如果使用pacman更新内核，必须要更新旧内核到滚动列表里的最新版本系统，而这又会产生冲突，比如我从`Linux64`更新到`Linux66`时:

```shell
Installing nvidia-utils(545.29.02-1) breaks dependency 'nvidia-utils=535.98-1' required by linux64-nvidia
```

使用mhwd-kernel手动安装新的内核，并且在遇到相关冲突的时候，卸载与旧内核有关的依赖、驱动

```shell
# 查看当前使用的内核
mhwd-kernel -li

# 卸载适配旧内核的Nvidia驱动和相关依赖比如cudnn cuda等
# 利用-Rdd标志强制卸载，无视依赖关系
sudo pacman -Rdd linux64-nvidia cuda cudnn

# 切换到新内核
sudo mhwd-kernel -i linux66

# 重启
reboot
```

内核切换完成后重启，由于是手动安装的新内核`linux66`，且适配旧内核`linux64`的Nvidia驱动还未卸载，重启后无法进入桌面

此时需要按`Ctrl+Alt+F2/F3`进入tty2/tty3等，卸载旧驱动，安装适配新内核的Nvidia驱动

```shell
# 使用mhwd查看当前使用的驱动版本
mhwd -li

# 查看mhwd所有的驱动列表
mhwd -la

# 卸载旧驱动(Nvidia闭源驱动)
sudo mhwd -r pci video-nvidia

# 如果提示cuda/cudnn等依赖冲突，可以先卸载它们
sudo pacman -R cudnn cuda

# 按照mhwd内建的策略，卸载完闭源驱动后会自动安装noveau的开源驱动
mhwd -li

> Installed PCI configs:
--------------------------------------------------------------------------------
                  NAME               VERSION          FREEDRIVER           TYPE
--------------------------------------------------------------------------------
           video-linux            2018.05.04                true            PCI


# 安装闭源驱动(策略可选两种: free/nonfree)，由于使用的Nvidia的显卡所以会安装video-nvidia
sudo mhwd -a pci nonfree

mhwd -li

> Installed PCI configs:
--------------------------------------------------------------------------------
                  NAME               VERSION          FREEDRIVER           TYPE
--------------------------------------------------------------------------------
          video-nvidia            2023.03.23               false            PCI

```

## 网络服务

### 锐捷认证

由于锐捷认证的启动脚本`rjsupplicant.sh`需要`root`权限，一开始是通过`rc-local.service`调用自己编写的`/etc/rc.local.d/rj_daemon.exp`，其中使用了`expect`处理需要输入密码鉴权的场景:

```shell
#! /usr/bin/expect
set timeout 10
set password "chenliwei"
spawn sudo /home/penistrong/Applications/rjsupplicant/rjsupplicant.sh
expect "sudo"
send "$password\n"
interact
```

但是脚本的启动顺序存在问题，锐捷认证服务需要在`network.target`启动后才能成功运行，因此改成以服务的方式开机启动，在`/usr/lib/systemd/system/`目录下新建`rjsupplicant.service`:

```shell
[Unit]
Description=RuiJie-Supplicant for Campus Network
After=syslog.target
After=network.target

[Service]
Type=simple
ExecStart=/home/penistrong/Applications/rjsupplicant/rjsupplicant.sh
ExecStop=kill -9 ${pidof /home/penistrong/Applications/rjsupplicant/x64/rjsupplicant}
ExecReload=kill -9 ${pidof /home/penistrong/Applications/rjsupplicant/x64/rjsupplicant} && /home/pensitrong/Applications/rjsupplicant/rjsupplicant.sh

[Install]
WantedBy=multi-user.target
```

并将其设置为开机启动服务

```shell
sudo systemctl daemon-reload

sudo systemctl enable rjsupplicant.service
```

## 开源软件

### Wallpaper-Engine-KDE-Plugin

从AUR更新catsout的[Wallpaper-Engine-Kde-Plugin](https://github.com/catsout/wallpaper-engine-kde-plugin)时总是碰到问题:

> Plugin lib version is inconsitent with plugin version

起初觉得是AUR打包的问题，看了PKGBUILD后又没有问题，跟作者官方repo里的编译步骤一致，百思不得其解

在[ISSUE-133](https://github.com/catsout/wallpaper-engine-kde-plugin/issues/133)中发现，作者让楼主使用`cmake .. -DCMAKE_INSTALL_PREFIX=/usr`解决楼主的lib插件安装前缀错误的问题(应该是`/usr`，但被安装到了`/usr/local`下)

这启发了我，但是我的CMake安装前缀是没有错的，猜想是否是qmake的问题

```shell
qmake -query

QT_SYSROOT:
QT_INSTALL_PREFIX:/home/penistrong/anaconda3
QT_INSTALL_ARCHDATA:/home/penistrong/anaconda3
QT_INSTALL_DATA:/home/penistrong/anaconda3
QT_INSTALL_DOCS:/home/penistrong/anaconda3/doc
QT_INSTALL_HEADERS:/home/penistrong/anaconda3/include/qt
QT_INSTALL_LIBS:/home/penistrong/anaconda3/lib
QT_INSTALL_LIBEXECS:/home/penistrong/anaconda3/libexec
QT_INSTALL_BINS:/home/penistrong/anaconda3/bin
QT_INSTALL_TESTS:/home/penistrong/anaconda3/tests
QT_INSTALL_PLUGINS:/home/penistrong/anaconda3/plugins
QT_INSTALL_IMPORTS:/home/penistrong/anaconda3/imports
QT_INSTALL_QML:/home/penistrong/anaconda3/qml
QT_INSTALL_TRANSLATIONS:/home/penistrong/anaconda3/translations
QT_INSTALL_CONFIGURATION:/home/penistrong/anaconda3
QT_INSTALL_EXAMPLES:/home/penistrong/anaconda3/examples
QT_INSTALL_DEMOS:/home/penistrong/anaconda3/examples
QT_HOST_PREFIX:/home/penistrong/anaconda3
QT_HOST_DATA:/home/penistrong/anaconda3
QT_HOST_BINS:/home/penistrong/anaconda3/bin
QT_HOST_LIBS:/home/penistrong/anaconda3/lib
QMAKE_SPEC:linux-g++
QMAKE_XSPEC:linux-g++
QMAKE_VERSION:3.1
QT_VERSION:5.15.2
```

其中的QT_INSTALL前缀竟然都指向Anaconda-base环境下的路径，这是因为我的终端默认激活了conda base环境，其下安装了qmake，导致执行脚本时查找的可执行文件qmake路径在Anaconda下，使用的也是conda的QT_INSTALL配置而不是系统环境里的配置

#### 解决方式

```shell
# Deactivate from base env to original terminal
conda deactivate

# Inspect qmake prefix
qmake -query

QT_SYSROOT:
QT_INSTALL_PREFIX:/usr
QT_INSTALL_ARCHDATA:/usr/lib/qt
QT_INSTALL_DATA:/usr/share/qt
QT_INSTALL_DOCS:/usr/share/doc/qt
QT_INSTALL_HEADERS:/usr/include/qt
QT_INSTALL_LIBS:/usr/lib
QT_INSTALL_LIBEXECS:/usr/lib/qt/libexec
QT_INSTALL_BINS:/usr/bin
QT_INSTALL_TESTS:/usr/tests
QT_INSTALL_PLUGINS:/usr/lib/qt/plugins
QT_INSTALL_IMPORTS:/usr/lib/qt/imports
QT_INSTALL_QML:/usr/lib/qt/qml
QT_INSTALL_TRANSLATIONS:/usr/share/qt/translations
QT_INSTALL_CONFIGURATION:/etc/xdg
QT_INSTALL_EXAMPLES:/usr/share/doc/qt/examples
QT_INSTALL_DEMOS:/usr/share/doc/qt/examples
QT_HOST_PREFIX:/usr
QT_HOST_DATA:/usr/lib/qt
QT_HOST_BINS:/usr/bin
QT_HOST_LIBS:/usr/lib
QMAKE_SPEC:linux-g++
QMAKE_XSPEC:linux-g++
QMAKE_VERSION:3.1
QT_VERSION:5.15.11

# Make and Install Plugin and its lib according to repo README
...
```
