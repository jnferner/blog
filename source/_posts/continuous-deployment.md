---
title: continuous-deployment
date: 2021-08-20 09:31:10
tags:
---

```
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
```

Not needed
```
AllowUsers blog-ci root
```
Don't forget root

`chroot`

```
passwd
touch /.autorelabel