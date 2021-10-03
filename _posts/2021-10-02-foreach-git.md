---
author: seekatar
title: ForEach-Git.ps1
tags:
 - powershell
 - git
---
ForEach-Git.ps1 runs scripts for each git repo folder

## Problem

I have a set of independently deployable microservices, each with its own repo, and I need to make some mass changes. I can use an editor like VSCode to do mass, multiline changes, but doing all the git commands can be painful.

## Solution

Create a script to execute commands on each repo folder.

```PowerShell
> ForEach-Git
```

<script src="https://gist.github.com/Seekatar/6fdf37c78e02312863066c8af99539fc.js"></script>