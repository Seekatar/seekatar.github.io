---
title: git reflog Saved the Day
tags:
 - git
 - reflog
excerpt: If you ever need to recover a commit, git reflog is your friend
cover: /assets/images/leaf9.webp
comments: true
layout: article
key: 20250317
---
![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

While working on a project, I unfortunately had a to have long-running branch. To make things easier on reviewers, I created branches off of it for each chunk of work. The branching was something like this:

```plaintext
main
  |
  +--- bigFeature
    |--- smallerFeature1
    +--- smallerFeature2
```

Each of the `smallerFeature` branches had several changes not in any other branch. I would keep the branches in sync with `main` by rebasing. On one of these rebases, I lost all the changes in `smallerFeature2`.

These are the steps I thought I did after changes were made by other developers on the `main` branch:

```bash
# update local main
git fetch origin main:main

# rebase bigFeature
git checkout bigFeature
git rebase Rebase main
git push -f

# rebase smallerFeature1
git checkout smallerFeature1
git rebase bigFeature
# fix some rebase conflicts
# fix some other issues after rebasing.
git push -f

# rebase smallerFeature2
git checkout smallerFeature2
git rebase main
```

Then I noticed that _all_ of the changes in `smallerFeature2` were gone 😱 and it now looked like `smallerFeature1`. That's when I started sweating. I'd been using Rider for .NET files and VSCode for pipeline YAML and SQL, so I could use their history to recover the changes. It would be a pain since there were quite a few files over several directories and I had to remember *all* the files I needed back. When Googling how to use VS Code to recover changes, I came across a post that mentioned "`git reflog` is your friend." I hadn't used that before so started reading up on it. The [official doc](https://git-scm.com/docs/git-reflog) says:

> Reference logs, or "reflogs", record when the tips of branches and other references were updated in the local repository.

Note that it does say "local repository," so this only helps when you mess up locally. If you do a clone, you will have only one entry in the reflog.

I ran `git reflog` and saw this (newer entries are at the top):

```plaintext
e65952d (origin/smallerFeature2, origin/smallerFeature1, smallerFeature2, smallerFeature1) HEAD@{1}: checkout: moving from smallerFeature1 to smallerFeature2
e65952d (origin/smallerFeature2, origin/smallerFeature1, smallerFeature2, smallerFeature1) HEAD@{2}: commit: fix merge
👆Now it the two branches are the same!
5f4b12c HEAD@{3}: rebase (finish): returning to refs/heads/smallerFeature1
5f4b12c HEAD@{4}: rebase (pick): hard app put
72b9766 HEAD@{5}: rebase (continue): Update app to have any number of levels
3cbffac HEAD@{6}: rebase (continue): add app crud
7e4fb92 HEAD@{7}: rebase (continue): add api
b7e3ea2 (origin/bigFeature, bigFeature) HEAD@{8}: rebase (start): checkout bigFeature
8b0c73d HEAD@{9}: checkout: moving from bigFeature to smallerFeature1
b7e3ea2 (origin/bigFeature, bigFeature) HEAD@{10}: commit: Fix for deleting market override
cb06705 HEAD@{11}: checkout: moving from smallerFeature1 to bigFeature
8b0c73d HEAD@{12}: commit: hard app put
3a236cb HEAD@{13}: checkout: moving from smallerFeature2 to smallerFeature1
👆This and above I don't want in smallerFeature2

8175c2b HEAD@{14}: commit: update scripts for analysis 👈 this is the last commit on smallerFeature2
6e8fbfa (HEAD) HEAD@{15}: rebase (finish): returning to refs/heads/smallerFeature2
6e8fbfa (HEAD) HEAD@{16}: rebase (continue): update import scripts
cb06705 HEAD@{17}: rebase (start): checkout bigFeature
5285b94 HEAD@{18}: checkout: moving from smallerFeature1 to smallerFeature2
```

To verify that the sha would get the file back I did this, which put me in detached head state, but all my files are now there (phew!)

```bash
git co 8175c2b
```

Just to be safe, I copied the folder and created a new branch on that commit:

```bash
git co -B smallerFeature2-backup
```

Now that the temperature of the room had returned to normal, I reset

```bash
git co smallerFeature2
git reset --hard 8175c2b
git push -f
```

Now my branch is back where it was!

Remember reflog is just for *local* changes.

Hope that helps!
