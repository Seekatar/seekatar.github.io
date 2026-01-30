---
title: Exploring PowerShell's Start-ThreadJob Part 3
tags:
 - powershell
 - start-threadjob
 - threading
excerpt: Exception handling in thread jobs.
cover: /assets/images/leaf15.png
comments: true
layout: article
key: 202601303
---
![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## Introduction

> This is the third of three posts in which I'll explore PowerShell's `Start-ThreadJob` cmdlet. In this post I'll how errors and exceptions are handled in thread jobs.

## Throwing Exceptions

Depending on your `$ErrorActionPreference` settings, you'll either get the exception thrown in `Receive-Job`.

If `$ErrorActionPreference` is set to `Continue` (the default), the exception is not thrown by `Receive-Job`. If you pass `-ErrorVariable` to `Receive-Job`, the exception is captured in that variable.

```powershell
function run {
  $job = Start-ThreadJob -ScriptBlock {
      Write-Host "2 ThreadJob started, about to throw exception..."
      throw "3 This is a test exception from ThreadJob"
  }

  Write-Host "1 About to receive job results."
  $job | Receive-Job -Wait -AutoRemoveJob -ErrorVariable jobError
  Write-Host "4 Finished receiving job results."
  Write-Host "5 jobError is '$jobError'"

}
run

1 About to receive job results.
2 ThreadJob started, about to throw exception...
Exception: 3 This is a test exception from ThreadJob
4 Finished receiving job results.
5 jobError is '3 This is a test exception from ThreadJob'
```

If the caller has `$ErrorActionPreference` set to `Stop`, the exception is thrown by `Receive-Job`.

```powershell
function run {
  $job = Start-ThreadJob -ScriptBlock {
      Write-Host "2 ThreadJob started, about to throw exception..."
      throw "3 This is a test exception from ThreadJob"
  }

  $ErrorActionPreference = 'Stop'
  Write-Host "1 About to receive job results."
  try {
      $job | Receive-Job -Wait -AutoRemoveJob
  } catch {
      Write-Host "4 Caught exception from Receive-Job: '$_'"
  }
}
run

1 About to receive job results.
2 ThreadJob started, about to throw exception...
4 Caught exception from Receive-Job: '3 This is a test exception from ThreadJob'
```

Either way works. I think it's a matter of preference whether you want to handle exceptions via try/catch or error variables.

### Write-Error

If you use `Write-Error` in the thread job, the behavior is similar to throwing an exception. In this case `$ErrorActionPreference` is set to `Stop` so we get the exception thrown by `Receive-Job`. Setting it to `Continue` would capture the error in an error variable.

```powershell
function run {
    $job = Start-ThreadJob -ScriptBlock {
        Write-Host "2 ThreadJob started, about to throw exception..."
        Write-Error "2.1 Write-Error message"
    }

  $ErrorActionPreference = 'Stop'
  Write-Host "1 About to receive job results."
  try {
      $job | Receive-Job -Wait -AutoRemoveJob
  } catch {
      Write-Host "4 Caught exception from Receive-Job: '$_'"
  }
}
run

1 About to receive job results.
2 ThreadJob started, about to throw exception...
4 Caught exception from Receive-Job: '2.1 Write-Error message'
```

Some applications write to stderr, and set lastexit code on error. These will cause an exception in `Receive-Job` as well if `$ErrorActionPreference` is set to `Stop`. Again, setting it to `Continue` would capture the error in an error variable.

```powershell
function run {
    $job = Start-ThreadJob -ScriptBlock {
        Write-Host "2 ThreadJob started, about to throw exception..."
        kubectl get asdfsad # causes exception to be thrown since caller has $ErrorActionPreference = 'Stop'
        $LastExitCode = 0
    }

  $ErrorActionPreference = 'Stop'
  Write-Host "1 About to receive job results."
  try {
      $job | Receive-Job -Wait -AutoRemoveJob
  } catch {
      Write-Host "4 Caught exception from Receive-Job: '$_'"
  }
}
run

1 About to receive job results.
2 ThreadJob started, about to throw exception...
4 Caught exception from Receive-Job: '2.1 Write-Error message'
```

## Summary

In this post, I covered showed how to get data into and out of thread jobs using `-InputObject`, `-ArgumentList`, and `$using:`. In the next post I'll cover exception handling in thread jobs.

## Links

MS Doc

- [about_Thread_Jobs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_thread_jobs)
- [Start-ThreadJob](https://learn.microsoft.com/en-us/powershell/module/threadjob/start-threadjob)
- [Receive-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/receive-job)
- [Get-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-job)
- [Remove-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-job)
- [Start-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/start-job?view=powershell-7.5) reference of the heavier alternative.
