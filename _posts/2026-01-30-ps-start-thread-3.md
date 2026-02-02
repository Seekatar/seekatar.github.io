---
title: Error handling in `Start-ThreadJob`
tags:
 - powershell
 - start-threadjob
 - threading
excerpt: Exploring PowerShell's Start-ThreadJob Part 3
cover: /assets/images/leaf15.png
comments: true
layout: article
key: 202601303
---
![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## Introduction

1. [Introduction to `Start-ThreadJob`](/2026-01-30-ps-start-thread-1.html)
1. [Passing parameters to `Start-ThreadJob`](/2026-01-30-ps-start-thread-2.html)
1. Error handling in `Start-ThreadJob` (this post)

In this post I'll explore how errors are handled in PowerShell's `Start-ThreadJob` cmdlet.

## Throwing Exceptions

Depending on your `$ErrorActionPreference` settings, you'll either get the exception thrown in `Receive-Job` or can capture it in an error variable.

If `$ErrorActionPreference` is set to `Continue` (the default), the exception is not thrown by `Receive-Job`. If you pass `-ErrorVariable` to `Receive-Job`, the exception is captured in that variable.

> I wrap the sample code in a function to make the numbered output cleaner.

```powershell
function run {
  $job = Start-ThreadJob -ScriptBlock {
      Write-Host "2 ThreadJob started, about to throw exception..."
      throw "3 This is a test exception from ThreadJob"
      Write-Host "Unreachable code"
  }

  $ErrorActionPreference = 'Continue' # 👈 default

  Write-Host "1 About to receive job results."
           # get the error in a variable 👇
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
      Write-Host "Unreachable code"
  }

  $ErrorActionPreference = 'Stop' # 👈 set the preference

  Write-Host "1 About to receive job results."
  try {
      $job | Receive-Job -Wait -AutoRemoveJob
      Write-Host "Unreachable code"
  } catch {
      Write-Host "4 Caught exception from Receive-Job: '$_'"
  }
}
run

1 About to receive job results.
2 ThreadJob started, about to throw exception...
4 Caught exception from Receive-Job: '3 This is a test exception from ThreadJob'
```

Either way works. I think it's a matter of preference whether you want to handle exceptions via try/catch or error variables. If you don't use either the exception is simply written to the error stream, but it's difficult to get the exception.

```powershell
function run {
  $job = Start-ThreadJob -ScriptBlock {
      Write-Host "2 ThreadJob started, about to throw exception..."
      throw "3 This is a test exception from ThreadJob"
      Write-Host "Unreachable code"
  }

  Write-Host "1 About to receive job results."
  $job | Receive-Job -Wait -AutoRemoveJob
  Write-Host "4 Finished receiving job results."
}
run

1 About to receive job results.
2 ThreadJob started, about to throw exception...
Exception: 3 This is a test exception from ThreadJob
4 Finished receiving job results.
```

### Write-Error

If you use `Write-Error` in the thread job, the behavior is similar to throwing an exception. In this case `$ErrorActionPreference` is set to `Stop` so we get the exception thrown by `Receive-Job`. Setting it to `Continue` could capture the error in an error variable.

```powershell
function run {
    $job = Start-ThreadJob -ScriptBlock {
        Write-Host "2 ThreadJob started, about to throw exception..."
        Write-Error "2.1 Write-Error message"
    }

  $ErrorActionPreference = 'Stop' # 👈 set the preference

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

Some applications write to stderr, and set `$LASTEXITCODE` code on error. These will cause an exception in `Receive-Job` as well if `$ErrorActionPreference` is set to `Stop`. Again, setting it to `Continue` could capture the error in an error variable.

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

In this post, I covered what happens when errors occur in the script block of `Start-ThreadJob`. It is the last in my series on thread jobs and I hope you have found them useful. My aim was to fill in some gaps in the documentation and provide practical examples of how to use thread jobs in PowerShell. There are other features I did not cover, so be sure to check the official documentation for more details.

## Links

MS Doc

- [about_Thread_Jobs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_thread_jobs)
- [Start-ThreadJob](https://learn.microsoft.com/en-us/powershell/module/threadjob/start-threadjob)
- [Receive-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/receive-job)
- [Get-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-job)
- [Remove-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-job)
- [Start-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/start-job?view=powershell-7.5) non-thread-based background jobs.
