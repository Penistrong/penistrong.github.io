# Penistrong's blog

Personal blog powered by jekyll.
Theme by [Hux](https://github.com/Huxpro/huxpro.github.io).

```yml
Plugins:
- jekyll-feed
- jekyll-paginate   # Paginator support
# - jekyll-spaceship  # Mathjax, emoji etc
```

## Install Dependencies

### CentOS / OpenCloud / RHEL

```sh
yum install ruby ruby-devel
gem install bundler jekyll
bundler install
```

## Deploy Blog Site

- Automatically build and deploy when file changes

```sh
# Hot upgrade mode as file server
jekyll serve --watch
```

- Incremental deploy with newly blog posts

```sh
# Incremental upgrade mode
jekyll build --source ${src_dir} --destination ${dst_dir} --incremental --watch
```

- Deploy to destination path from zero

```sh
jekyll build --source ${src_dir} --destination ${dst_dir}
```