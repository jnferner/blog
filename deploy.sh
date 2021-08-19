rm -rf public/ && yarn hexo deploy && rsync -avz --no-whole-file public/ jnf:/usr/share/nginx/html/jnferner.com/blog/

