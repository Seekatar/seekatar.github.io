---
author: seekatar
title: ForEach-Git.ps1
tags:
 - powershell
 - git
 - code
excerpt: Run a scriptblock in each git repo folder
cover: /assets/images/fern-leaf-1372477-1280x960.jpg
comments: true
layout: article
---

![image](/assets/images/fern-leaf-1372477-1280x960.jpg){: width="{{ site.imageWidth }}" }

## Problem

I have a set of independently deployable microservices, each with its own repo, and I need to make some mass changes. I can use an editor like VSCode to do mass, multiline changes, but doing all the git commands can be painful.

## Solution

Create a script to execute commands on each repo sub folder. It's called `ForEach-Git` with an alias of `feg` and is [here](https://gist.github.com/Seekatar/6fdf37c78e02312863066c8af99539fc). Check out the comment-based help, with examples. It runs on Windows and Linux, and requires Posh-Git to be installed.

Without any parameters, the default scriptblock returns objects with the folder names, branch, and status

```PowerShell
/home/test/code> feg

Name     Branch Working
----     ------ -------
ServiceA main     False
ServiceB main      True
ServiceC main     False
ServiceD main     False
```

The script works on subfolders that have a `.git` subfolder, and always returns to your current directory. You usually pass in a scriptblock that runs in the repo's folder. The scriptblock is passed the directory object, and gitstatus object, if you want to use them.

## Some Common Usages

Create a new branch for a set of folders. You can pipe an array of names through, or use -HasWorking or -OnBranch to filter.

```PowerShell
"ServiceA","ServiceB" | feg { git checkout -B 'test' } -ShowFolder
```

Commit all the changes on repos that have outstanding changes and push them

```PowerShell
feg { git add . && git commit -m 'important' && git push } -HasWorking -ShowFolder
```

Merge `main` into all the repos currently in the `test` branch

```PowerShell
feg { git fetch origin main:main && git merge main } -OnBranch test -ShowFolder
```

Push all your changes and call the `New-PR` script to create a PR in Azure DevOps (new blog coming)

```PowerShell
feg { git push -u origin test && New-PR } -OnBranch test -ShowFolder
```

Once all your changes are complete, get `main` and delete the `test` branch

```PowerShell
feg { git fetch origin main:main && git checkout main && git branch -D test } -OnBranch test -ShowFolder
```

## Scenarios

For the test, lets create a local "remote" repo. Note using semicolon for directory creation to avoid it short-circuiting if it fails, but && for the others since they must all succeed.

```PowerShell
mkdir /home/test/gitbak

feg { param($dir,$gitStatus)  mkdir "/home/test/gitbak/$($dir.name)" ; git remote add origin "/home/test/gitbak/$($dir.name)" && cd "/home/test/gitbak/$($dir.name)" && git init }

Initialized empty Git repository in /home/test/gitbak/ServiceA/.git/
Initialized empty Git repository in /home/test/gitbak/ServiceB/.git/
Initialized empty Git repository in /home/test/gitbak/ServiceC/.git/
Initialized empty Git repository in /home/test/gitbak/ServiceD/.git/
```

For a few folders let's check out a branch, `test`. The `ShowFolder` switch shows the folder names as it processes them, and can help when resuming in the event of an error (as I'll show below).

```PowerShell
/home/test/code> "ServiceA","ServiceC","ServiceD" | feg { git co -B test } -ShowFolder

>>> 0 ServiceA folder
Switched to a new branch 'test'

>>> 2 ServiceC folder
Switched to a new branch 'test'

>>> 3 ServiceD folder
Switched to a new branch 'test'
```

Let's set up a failure to show how to resume. First just update A with the remote.

```PowerShell
/home/test/code> feg -Include "ServiceA" { git push -u origin test }
Enumerating objects: 9, done.
Counting objects: 100% (9/9), done.
Delta compression using up to 4 threads
Compressing objects: 100% (3/3), done.
Writing objects: 100% (9/9), 633 bytes | 633.00 KiB/s, done.
Total 9 (delta 0), reused 0 (delta 0)
To /home/test/gitbak/ServiceA
 * [new branch]      test -> test
Branch 'test' set up to track remote branch 'test' from 'origin'.
```

Now let's try pushing all on `test`. Note that A works, but C fails. The error messages says we can use -StartWith 1 to start with C.

```PowerShell
/home/test/code> feg  { git push } -OnBranch test -ShowFolder

>>> 0 ServiceA folder
Everything up-to-date

>>> 1 ServiceC folder
fatal: No configured push destination.
Either specify the URL from the command-line or configure a remote repository using

    git remote add <name> <url>

and then push using the remote name

    git push <name>

WARNING: Error processing /home/test/code/ServiceC
WARNING: To processing again from there, add '-StartWith 1'
Exception: /mnt/c/code/ccc/Tools/PowerShell/ForEach-Git.ps1:118
Line |
 118 |  …                              throw "Non-zero exit code $LASTEXITCODE"
     |                                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Non-zero exit code 128
```

We can fix that by setting the remote, but skipping A.

```PowerShell
/home/test/code> feg  { git push -u origin test } -OnBranch test -ShowFolder -StartWith 1

>>> 0 ServiceA folder

>>> 1 ServiceC folder
Branch 'test' set up to track remote branch 'test' from 'origin'.
Everything up-to-date

>>> 2 ServiceD folder
Branch 'test' set up to track remote branch 'test' from 'origin'.
Everything up-to-date
```

This was a rather contrived example, but there are many times I've got half way through many repos and got an error and had to restart from where I left off since the commands couldn't be re-run on the previous repos (e.g. delete a branch).