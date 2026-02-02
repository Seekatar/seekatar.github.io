---
title: Introduction to `Start-ThreadJob`
tags:
 - powershell
 - start-threadjob
 - threading
excerpt: Exploring PowerShell's Start-ThreadJob Part 1
cover: /assets/images/leaf15.png
comments: true
layout: article
key: 20260130
---
![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## Introduction

This is the first of three posts in which I'll explore PowerShell's `Start-ThreadJob` cmdlet. My goal is to cover some of the subtleties of using thread jobs that are not well documented elsewhere.

1. Introduction to `Start-ThreadJob` (this post)
1. [Passing parameters to `Start-ThreadJob`](/2026-01-30-ps-start-thread-2.html)
1. [Error handling in `Start-ThreadJob`](/2026-01-30-ps-start-thread-3.html)

`Start-ThreadJob` allows you to run code in the background using threads. This post will cover the basics of running a thread job and getting its output.

> In my [K8sUtils](https://www.powershellgallery.com/packages?q=k8sutils) PowerShell module, I found an edge case where I couldn't get logs since they were created by a blocking command and removed by the time it returned. To solve that, I started a thread job to get the logs while the blocking command was running. During that implementation, I found there are some subtleties to using `Start-ThreadJob` that are not well documented. That is the impetus for this series of posts.

There is also a `Start-Job` cmdlet which kicks off a separate process locally or remotely. I will not cover that here.

## Using Start-ThreadJob

To run a background thread, you pass it a script block. If you don't use the `-Name` parameter, it will have the name `JobN`, where N is a number.

```powershell
# I'll re-use the script block in the examples below
$sb = {
    for ($i = 1; $i -le 2; $i++) {
        Write-Host "Write-Host in ScriptBlock $i"
        Write-Output $i
        Start-Sleep -Seconds .5
    }
}
$job = Start-ThreadJob -ScriptBlock $sb
```

That will start a thread in the background. You can check the status of the job with:

```powershell
Get-Job -Id $job.Id

Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
--     ----            -------------   -----         -----------     --------             -------
3      Job3            ThreadJob       Running       True            PowerShell           …
```

The happy path `State`s will be `Running` then `Completed`, but there are others. The `HasMoreData` property indicates if there is output waiting to be received, which you get with `Receive-Job`.

```powershell
Receive-Job $job

1
2
Write-Host in Start-ThreadJob 1
Write-Host in Start-ThreadJob 2
```

To get the output of the job in a variable `$x` do this. Note that `Write-Host` still goes to the console, while `Write-Output` goes to the variable.

```powershell
$job = Start-ThreadJob -ScriptBlock $sb
Start-Sleep -Seconds 3 # pretend to do other work here
$x = Receive-Job $job

Write-Host in Start-ThreadJob 1
Write-Host in Start-ThreadJob 2

$x
1
2
```

At this point you have received the output from the jobs, but they are still out there. You can see the status of them with `Get-Job`

```powershell
Get-Job

Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
--     ----            -------------   -----         -----------     --------             -------
3      Job3            ThreadJob       Completed     False           PowerShell           …
4      Job4            ThreadJob       Completed     False           PowerShell           …
```

If you `Receive-Job` again, you'll get nothing since `HasMoreData` is `False`. To remove the jobs, use `Remove-Job`

You can use `Receive-Job` to wait for a job and delete it in one step. In this example, you'll see the output as it is produced.

```powershell
Start-ThreadJob -ScriptBlock $sb | Receive-Job -Wait -AutoRemoveJob

Write-Host in ScriptBlock 1
1
Write-Host in ScriptBlock 2
2
```

Note that running with `-Wait` the `Write-Host` and `Write-Output` are interleaved since it is receiving the output as it is produced. As before, you can capture the output in a variable:

```powershell
$x = Start-ThreadJob -ScriptBlock $sb | Receive-Job -Wait -AutoRemoveJob

Write-Host in ScriptBlock 1
Write-Host in ScriptBlock 2

$x
1
2
```

Since all the `Write-*` cmdlets write to different streams, if you get the output after the job is complete, they are not in time order. This can be annoying if you need messages in the order they were produced. (In K8sUtils, I use a logging function that writes to `Write-Host` so I capture everything in order.)

```powershell
$sb = {
    for ($i = 1; $i -le 2; $i++) {
        Write-Debug "Write-Debug $i" -Debug
        Write-Verbose "Write-Verbose $i" -Verbose
        Write-Information "Write-Information $i" -InformationAction Continue
        Write-Warning "Write-Warning $i" -WarningAction Continue
        Write-Error "Write-Error $i" -ErrorAction Continue
        Write-Host "Write-Host $i"
        Write-Output $i
        Start-Sleep -Seconds .5
    }
}
$job = Start-ThreadJob -ScriptBlock $sb -Verbose -Debug
Start-Sleep -Seconds 3 # pretend to do other work here
$x = Receive-Job $job -Verbose -Debug -InformationAction Continue

Write-Error: Write-Error 1
Write-Error: Write-Error 2
VERBOSE: Write-Verbose 1
VERBOSE: Write-Verbose 2
DEBUG: Write-Debug 1
DEBUG: Write-Debug 2
WARNING: Write-Warning 1
WARNING: Write-Warning 2
Write-Information 1
Write-Host 1
Write-Information 2
Write-Host 2

$x
1
2
```

Couple of things to note here. If you don't use the `-Verbose`, `-Debug`, and `-InformationAction Continue` parameters on `Receive-Job`, you won't see those streams' output. Also notice that `Write-Information` and `Write-Host` are still interleaved since they both write to the host directly. Here, those parameters are not included and we only get error, warning and host output.

```powershell
Start-ThreadJob -ScriptBlock $sb -Verbose -Debug | Receive-Job -Wait -AutoRemoveJob

WARNING: Write-Warning 1
Write-Error: Write-Error 1
Write-Host 1
WARNING: Write-Warning 2
Write-Error: Write-Error 2
Write-Host 2
WARNING: Write-Warning 3
Write-Error: Write-Error 3
Write-Host 3
WARNING: Write-Warning 4
Write-Error: Write-Error 4
Write-Host 4
WARNING: Write-Warning 5
Write-Error: Write-Error 5
Write-Host 5
```

As a final example, if you have a long-running job, you can receive it periodically to get intermediate output.

```powershell
$sb = {
    for ($i = 1; $i -le 10; $i++) {
        Write-Host "Write-Host in ScriptBlock $i"
        Start-Sleep -Seconds 1
    }
}
$job = Start-ThreadJob -ScriptBlock $sb
Start-Sleep -Seconds 2;Receive-Job $job

Write-Host in ScriptBlock 1
Write-Host in ScriptBlock 2
Write-Host in ScriptBlock 3

Start-Sleep -Seconds 2;Receive-Job $job

Write-Host in ScriptBlock 4
Write-Host in ScriptBlock 5

Receive-Job $job -Wait -AutoRemoveJob

Write-Host in ScriptBlock 6
Write-Host in ScriptBlock 7
Write-Host in ScriptBlock 8
Write-Host in ScriptBlock 9
Write-Host in ScriptBlock 10
```

## Summary

In this post, I covered the basics of using `Start-ThreadJob` to run code in the background using threads and getting its output. I showed how to start a thread job, check its status, receive its output, and remove it when done. In future posts, I'll cover passing parameters to thread jobs and error handling.

There are other features of `Start-ThreadJob` and `Receive-Job` that I didn't cover here, such as running multiple jobs in parallel and controlling the number of concurrent threads. Check the links below for more information.

## Links

MS Doc

- [about_Thread_Jobs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_thread_jobs)
- [Start-ThreadJob](https://learn.microsoft.com/en-us/powershell/module/threadjob/start-threadjob)
- [Receive-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/receive-job)
- [Get-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-job)
- [Remove-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-job)
- [Start-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/start-job?view=powershell-7.5) non-thread-based background jobs.
