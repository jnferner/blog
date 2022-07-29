rm -rf blog/ && yarn hexo deploy && rsync -avz --no-whole-file blog/ hhh:/usr/share/nginx/html/hohenheim.ch/blog/

