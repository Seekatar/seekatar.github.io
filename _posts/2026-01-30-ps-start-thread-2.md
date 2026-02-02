---
title: Passing parameters to Start-ThreadJob
tags:
 - powershell
 - start-threadjob
 - threading
excerpt: Exploring PowerShell's Start-ThreadJob Part 2
cover: /assets/images/leaf16.png
comments: true
layout: article
key: 202601302
---
![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## Introduction

1. [Introduction to Start-ThreadJob](/2026/01/30/ps-start-thread-1.html)
1. Passing parameters to `Start-ThreadJob` (this post)
1. [Error handling in Start-ThreadJob](/2026/01/30/ps-start-thread-3.html)

In this post I'll explore the multiple ways to pass data into and out of thread jobs. I'll cover these three methods:

- `-InputObject` parameter
- `Arguments` parameter
- The `$using:` scope modifier

## Using -InputObject

This passes in an object that will be available in the thread job via the automatic `$input` variable.

```powershell
$object = @{
    Environment = "Production"
    Servers = @("server1", "server2", "server3")
}

Start-ThreadJob -ScriptBlock {
  $input.GetType().Name
  $o = $input | Select-Object -First 1
  "Environment is $($o.Environment)"
} -InputObject $object |
Receive-Job -Wait -AutoRemoveJob

<GetReadEnumerator>d__20
Environment is Production
```

This is my least preferred method since the `$input` variable isn't the parameter you pass in, but an enumerator.

## Using -ArgumentList

Using  `-ArgumentList` is similar to other PowerShell cmdlets that accept arguments. You pass in a list of arguments you want to use and consume them via a `param()` block.

```powershell
$i = 42

Start-ThreadJob -ScriptBlock {
    param($intValue, $objectRef, $timestampValue)
        "`$intValue $intValue"
        "`$objectRef.environment: $($objectRef.Environment)"
        "`$timestampValue: $timestampValue"
    } -ArgumentList $i, $object, (Get-Date) |
Receive-Job -Wait -AutoRemoveJob

$intValue 42
$objectRef.environment: Production
$timestampValue: 01/30/2026 15:08:52
```

This works pretty well. What you pass in on the `-ArgumentList` is the same as what you get in the `param()` block. I like this a bit better.

## Using $using:

If you've used script blocks in other situations, you may be familiar with the `$using:` scope modifier. This allows you to reference variables from the parent scope directly inside the script block.

```powershell
$timestamp = Get-Date
Start-ThreadJob -ScriptBlock {
        "`$intValue $using:i"
        "`$objectRef.environment: $(($using:object).Environment)"
        "`$timestampValue: $using:timestamp"
    } |
Receive-Job -Wait -AutoRemoveJob
```

This is similar to `-ArgumentList`, but you don't need a `param()` block. This is my preferred method since it's more concise.

## Getting Output

As we saw in [part 1](/2026-01-30-ps-start-thread-1.html), anything written to output (implicitly, with `Write-Output`, or `return`) will be what is returned by `Receive-Job`.

```powershell
($s,$i,$h) = Start-ThreadJob -ScriptBlock {
        Write-Output "Output message"
        42
        return @{ Timestamp = Get-Date; Status = "Completed" }
    } |
Receive-Job -Wait -AutoRemoveJob

$s

Output message

$i

42

$h

Name                           Value
----                           -----
Status                         Completed
Timestamp                      1/30/2026 3:19:59 PM
```

In this (contrived) example, the output is a tuple of string, integer, and hashtable.

## Changing Values in the Caller's Scope

Instead of passing something in and getting something out, what if you (heaven forbid) want to change an object in the caller's scope? If you have a reference type (like a hashtable or custom object), you can do this using `$using:`.

```powershell
$result = Start-ThreadJob -ScriptBlock {
        ($using:object).Environment = "Staging"
    } |
Receive-Job -Wait -AutoRemoveJob

$object.Environment

Staging
```

For a value type (like an integer or string), you need to get a variable object and pass that into the thread job.

```powershell
$outerVar = 42
$varRef = Get-Variable -Name outerVar

$result = Start-ThreadJob -ScriptBlock {
        ($using:varRef).Value = 100
    } |
Receive-Job -Wait -AutoRemoveJob

$outerVar
100
```

## Summary

In this post, I showed how to get data into and out of thread jobs using `-InputObject`, `-ArgumentList`, and `$using:`. In the next post I'll cover error handling in thread jobs.

## Links

MS Doc

- [about_Thread_Jobs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_thread_jobs)
- [Start-ThreadJob](https://learn.microsoft.com/en-us/powershell/module/threadjob/start-threadjob)
- [Receive-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/receive-job)
- [Get-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-job)
- [Remove-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-job)
- [Start-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/start-job?view=powershell-7.5) non-thread-based background jobs.

