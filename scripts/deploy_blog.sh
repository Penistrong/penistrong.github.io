#!/bin/bash
# 执行方式 sudo bash ./deploy_blog.sh deploy_list

# 用于个人网站生成静态博客页面(非Github Action)
# 目前域名有www.pensitrong.xyz和.top两个
# 读取deploy_list文件，每行一个域名，生成对应的静态博客页面
source ./deploy_env

loop=0
while read line
do
    destination="$DESTINATION_PATH_PREFIX/$line/$DESTINATION_PATH_SUFFIX"
    echo $destination

    sed -i "s#url: \"$OG_SITE_URL\"#url: \"$line\"#g" ../_config.yml
    jekyll build --source ../ --destination $destination
    sed -i "s#url: \"$line\"#url: \"$OG_SITE_URL\"#g" ../_config.yml

    loop=`expr $loop + 1`
done < $1

echo "Deployed $loop blog site!"
