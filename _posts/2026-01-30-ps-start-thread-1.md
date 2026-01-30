---
title: Exploring PowerShell's Start-ThreadJob Part 1
tags:
 - powershell
 - start-threadjob
 - threading
excerpt: Using Start-ThreadJob in PowerShell
cover: /assets/images/leaf15.png
comments: true
layout: article
key: 20260130
---
![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## Introduction

> This is the first of three posts in which I'll explore PowerShell's `Start-ThreadJob` cmdlet. It allows you to run some code in the background using threads. This post will cover the basics of running a thread job and getting its output. Later, I'll cover passing parameters to thread jobs and handling exceptions.

In my [K8sUtils](https://www.powershellgallery.com/packages?q=k8sutils) PowerShell module, I found an edge case where I couldn't get logs since they were created by a blocking command and removed by the time it returned. I thought I could solve that my having a background job start and get the logs while the blocking command was running.

I had used `Start-Job` before, and when looking through the docs, I found `Start-ThreadJob`, which is a better, faster, and more lightweight solution.

## Using Start-ThreadJob

To run a background thread, you pass it a script block:

```powershell
# we'll re-use the script block in the examples below
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
3      Job3            ThreadJob       Completed     True            PowerShell           …
```

To get the output of the job, you receive it:

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
Start-Sleep -Seconds 3 # pretend we're doing other work here
$x = Receive-Job $job

Write-Host in Start-ThreadJob 1
Write-Host in Start-ThreadJob 2

$x
1
2
```

At this point we've received the output from the jobs, but they are still out there. You can see the status of them with `Get-Job`

```powershell
Get-Job

Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
--     ----            -------------   -----         -----------     --------             -------
3      Job3            ThreadJob       Completed     False           PowerShell           …
4      Job4            ThreadJob       Completed     False           PowerShell           …
```

If you `Receive-Job` again, you'll get nothing since nothing more has been output since the last `Receive-Job`. To remove the jobs, use `Remove-Job`

You can use `Receive-Job` to wait for a job and delete it in one step. In this example we'll see the output as it is produced.

```powershell
Start-ThreadJob -ScriptBlock $sb | Receive-Job -Wait -AutoRemoveJob

Write-Host in ScriptBlock 1
1
Write-Host in ScriptBlock 2
2
```

Note that running with `-Wait` the `Write-Host` and `Write-Output` are interleaved since we are receiving the output as it is produced. As before, we can capture the output in a variable:

```powershell
$x = Start-ThreadJob -ScriptBlock $sb | Receive-Job -Wait -AutoRemoveJob

Write-Host in ScriptBlock 1
Write-Host in ScriptBlock 2

$x
1
2
```

Since all the `Write-*` cmdlets write to different streams, if you get the output after the job is complete, they are not in time order. This can be annoying if you need messages in the order they were produced. (In my K8sUtils I already had a logging function that wrote to `Write-Host` so I could capture everything in order.)

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
Start-Sleep -Seconds 3 # pretend we're doing other work here
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

Couple of things to note here. If you don't use the `-Verbose`, `-Debug`, and `-InformationAction Continue` parameters on `Receive-Job`, you won't see those streams' output. Also notice that `Write-Information` and `Write-Host` are still interleaved since they both write to the host directly.

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

Receive-Job $job -Wait -AutoRemoveJob

Write-Host in ScriptBlock 4
Write-Host in ScriptBlock 5
Write-Host in ScriptBlock 6
Write-Host in ScriptBlock 7
Write-Host in ScriptBlock 8
Write-Host in ScriptBlock 9
Write-Host in ScriptBlock 10
```

## Summary

In this post, I covered the basics of using `Start-ThreadJob` to run code in the background using threads and getting its output. I showed how to start a thread job, check its status, receive its output, and remove it when done. In future posts, I'll cover passing parameters to thread jobs and handling exceptions.

There are other features of `Start-ThreadJob` and `Receive-Job` that I didn't cover here, such as running multiple jobs in parallel and controlling the number of concurrent threads. Check the links below for more information.

## Links

MS Doc

- [about_Thread_Jobs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_thread_jobs)
- [Start-ThreadJob](https://learn.microsoft.com/en-us/powershell/module/threadjob/start-threadjob)
- [Receive-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/receive-job)
- [Get-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-job)
- [Remove-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-job)
- [Start-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/start-job?view=powershell-7.5) reference of the heavier alternative.
