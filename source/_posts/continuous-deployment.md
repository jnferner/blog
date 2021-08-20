---
title: Setting up Continuous Deployment
date: 2021-08-20 09:31:10
categories:
    - devops
    - meta
tags:
    - continuous-deployment
---

The best thing to start with is meta, right?

As a big proponent of automation in development, I have a confession to make: I've never setup continuous deployment myself, I've always left that task to teammates. What better opportunity than this very blog to learn the ropes?

## What is Continuous Deployment?
The newbie's way of deploying a website on a server is to copy all their content, e.g. via `scp`. More advanced smartypants will learn about `rsync` and that it can be used to only send the difference in files over the wire, making deployment quicker. If entering these commands becomes too repetitive, you might create a `deploy.sh` that you run after every merge to `main`. At least, I did.
But we can make the process better. 1000x better. You remember how [continuous integration](https://docs.github.com/en/actions/guides/about-continuous-integration) was a real eye opener once you experienced how much easier life became when all tests ran automatically on each merge? You can enjoy more of the wonderful world of automation when you also deploy your software automatically afterwards!

## Setup
As this is a case study, I will show you the minimum of the tools I used to get new blog posts automatically uploaded. Note that the exact workflow will be different for other use cases. In particular, I don't need to run tests before deployment and don't need to version my deployment artifacts. You should however be able to puzzle it together yourself once you know the basics.
Anyways, for this post we use the following stack.
- A linux server, here a Fedora hosted by [DigitalOcean](https://m.do.co/c/bac052f0a30b)
- A reverse proxy, here nginx
- The [GitHub repo](https://github.com/jnferner/blog) for this blog with GitHub's [Actions](https://github.com/features/actions) feature
- The [ssh-deploy Action](https://github.com/easingthemes/ssh-deploy)
- For building this blog in particular, [hexo](https://hexo.io/)

## Setting up the server
### Hosting Directory
I will not even attempt to describe how to setup nginx for hosting static web pages. I also cannot link you to a tutorial with a good conscience, since I find most of them mind-boggling. I learned what I know about nginx directly from friends (thanks Ruben!).
That said, any way of hosting will do. You'll need to find out where you are supposed to place your files though. For example, on nginx, you'll need to place them in a subfolder of `/usr/share/nginx/html/`. Another common one is `/var/www/html`.
For the rest of this post, we will assume that the files need to be placed under `/usr/share/html/blog` as a placeholder name, but do remember to use your own path instead!

### Dedicated User
You do not want to give any service root access to your entire machine, so you should setup a dedicated user on your server. Here, we 
will call it `continuous-deployment`. The following creates the user and sets up the permissions. Note that that the command for adding a user is specific to the distribution you are using. `useradd` is for Fedora and CentOS, `adduser` is for Ubuntu/Debian.
```bash
useradd continuous-deployment
chown continuous-deployment:continuous-deployment /usr/share/html/blog
```
We will deploy the files via SSH, so we need to setup SSH keys. You will again not want to use your normal keys, since they wield too much power. Note that `ssh-deploy` says that it requires PEM keys. I have not tried RSA or ed25519, they might work as well, but I am not tempting fate. To generate your keys, run the following on your client, not your server. Note that we give the keys the name `id_pem_continuous_deployment`, but you may use another one.
```bash
ssh-keygen -m PEM -t rsa -b 4096 -f $HOME/.ssh/id_pem_continuous_deployment
```

The user also needs to be able to accept SSH connections. Again, the specifics are different for each distribution, but it will always entail copying the public key to the `authorized_keys` file. On your client, copy your public key. You can print it with the following and then select and copy it:
```bash
cat ~/.ssh/id_pem_continuous_deployment.pub
```
Note that on macOS, this can be done in one step:
```bash
pbcopy < ~/.ssh/id_pem_continuous_deployment.pub
```
If you type this by hand, do not forget the `.pub` at the end!
Then, on your server, login as the new account and paste the public key into `~/.ssh/authorized_keys`. Probably neither the `~/.ssh/` directory nor the file exist yet, so you'll have to create them.
```bash
su continuous-deployment
mkdir ~/.ssh
vim ~/.ssh/authorized_keys
```
In `vim`, paste the key via `G`, `i`, `CTRL-V` and save it via `:wq`. You'll need to set the file permissions like this:
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

Now, on your client, you should be able to SSH into your server with this account. We will assume your server's address is `example.com`, but you can just as well use an IP here.
```bash
ssh continuous-deployment@example.com -i ~/.ssh/id_pem_continuous_deployment  
```
Make sure this works and that you have access to `/usr/share/html/blog`, otherwise the continuous deployment will not work.

Some sources claim that it is necessary to add your user to the `AllowUser` list in `/etc/ssh/sshd_config`:
```bash
AllowUser   continuous-deployment root
```
Then, restart your SSH daemon:
```
systemctl restart sshd
```
This step was not necessary for me, but it might help you.
If this line does not yet exist and you add it yourself, make sure to include the root user, otherwise you will have locked yourself out of machine!

### Troubleshooting
#### The directory `~/.ssh` does not exist
You've never used SSH on this machine then. No problem, simply create it:
```bash
mkdir ~/.ssh
```

#### I can't connect to the server
Some machines do not like an SSH keylength of 4096. Try the steps above again, but replace `rsa -b 4096` with `rsa -b 2048`.
Before this, feel free to delete the old keys on the client:
```bash
rm ~/.ssh/id_pem_continuous_deployment ~/.ssh/id_pem_continuous_deployment.pub
```
And remove the old public key from the server's `authorized_keys`

Also, make sure that you added the key to the `authorized_keys` file of the right user. The home directory should therefore not be the one from root, but from `continuous-deployment`

#### I locked myself out of the system and my account does not even have a password with which I could access the console. Did I just brick my server?
Boot from a recovery disk. For DigitalOcean, there is a [dedicated feature for this](https://docs.digitalocean.com/products/droplets/resources/recovery-console/).
Then, `chroot` into your system and set a password with `passwd`. Caveat: If you run SELinux, you must let the system relabel. This is done by creating a simple file and rebooting the system. Your commands in the `chrooted` session are thus:

```bash
passwd
touch /.autorelabel
reboot -f
```

## GitHub Workflow
In your repo, create a directory `.github` with a subdirectory `workflows`. In there, create a file `deployment.yaml`.
Enter the following content and edit it to your needs:
```yaml
name: Deployment

on:
  push:
    branches:
      - main

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v1
      - name: Install Node.js
        uses: actions/setup-node@v1
        with:
          node-version: '14.x'
      - name: Install npm dependencies
        run: yarn install
      - name: Run build task
        run: yarn hexo deploy
      - name: Deploy to Server
        uses: easingthemes/ssh-deploy@v2.1.7
        env:
          SSH_PRIVATE_KEY: ${{ secrets.SERVER_SSH_KEY }}
          ARGS: "-avz --delete"
          SOURCE: "public"
          REMOTE_HOST: ${{ secrets.REMOTE_HOST }}
          REMOTE_USER: ${{ secrets.REMOTE_USER }}
          TARGET: ${{ secrets.REMOTE_TARGET }}
          EXCLUDE: "/.git, /.github, /dist/, /node_modules/"
```
This config runs whenever you push a commit to `main`, including when merging pull requests.
See the line `SOURCE: "public"`? That tells `ssh-deploy` which directory you want to deploy. Change this to your use case, but remember that as far as I know, `ssh-deploy` does not allow renaming, so you will have to add a new step in order to `mv` it on the server.

By the way, you might have noticed, that the Node version is a bit outdated. That is because as of the time of writing, newer versions do not play well with macOS Big Sur.

After your changes, add this file to git and push it. If you feel a bit lost, check out the [project structure of this blog](https://github.com/jnferner/blog) for help.

### Got a Secret, Better Keep it 
You've probably spotted the lines that look like `${{ secrets.FOO }}`. These read [GitHub secret](https://docs.github.com/en/actions/reference/encrypted-secrets), which you can use so savely store sensitive data like private keys. Speaking of which, you can copy your private key on your client similar to how you copied the public key, just omit the `.pub` ending:
```bash
cat ~/.ssh/id_pem_continuous_deployment
```
or again on macOS:
```bash
pbcopy < ~/.ssh/id_pem_continuous_deployment
```
Then paste that key as the value for the secret `SERVER_SSH_KEY` in your settings. I have to stress that you should *never* enter this information anywhere else. Not a file, not in a chat and especially not in `deployment.yaml`.

With the assumptions we have made so far, the secrets should look something like this:
#### SERVER_SSH_KEY
```
-----BEGIN RSA PRIVATE KEY-----
<A long long wall of random symbols>
-----END RSA PRIVATE KEY-----
```

#### REMOTE_HOST
```
example.com
```
Do not copy paste this value, it will not be valid. Enter your own server domain or IP address.

#### REMOTE_USER
```
continuous-deployment
```

#### REMOTE_TARGET
```bash
/usr/share/html
```
Note that this will be placed in front of the `SOURCE` you specified in the `deployment.yaml`. So, if `SOURCE` is set to `blog`, your files will go to `/usr/share/html/blog`
## Let's see the results
Create and merge a new dummy pull request. I always recommend renaming `README.md` to `readme.md`, no one wants to get screamed at. By the way, have you already added a `license.txt`?

Afterwards, you should see your deployment under the GitHub tab `Actions`. If there is a green circle, congratulations, your directory has made it to your server! 

### Troubleshooting
#### rsync failed somehow
Verify that you can manually SSH into the account as described earlier via
```bash
ssh continuous-deployment@example.com -i ~/.ssh/id_pem_continuous_deployment 
```
If this does not work, consult the earlier troubleshoot section. Otherwise, if the rsync still fails, you probably
have made a mistake in your GitHub secrets. Have you accidentally copied the public key instead of the private key?

#### The rsync worked, but my webserver cannot access the files
Something with your permissions might be wrong. Run the following to fix the ownership:
```bash
chown continuous-deployment:continuous-deployment /usr/share/html/blog
```
If you use SELinux, the following will help as well:
```bash
ls -lrtZ * && restorecon -v -R .
```
I run this one so many time that I have it aliased by now as `fixselinux`.

#### Everything works, but my server still shows the outdated files
Have the files been copied to right path? Check your `REMOTE_TARGET` secret as described above.
