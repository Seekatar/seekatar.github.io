---
# author: seekatar
title: Unloading Assemblies in .NET
tags:
 - dotnet
 - assemblies
excerpt: Exercise in unloading assemblies in .NET 6 (Core)
cover: /assets/images/2022-09-04-sin.png
comments: true
layout: article
key: unload-assembly
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## The Problem

In a recent project, I build assemblies on-the-fly and load and run them. The assemblies are small, so loading a bunch probably isn't a big issue. But still, it kinda bugged me that it loads so many. And when a new version is created, another assembly is loaded (different name, of course), but now the old one that already is loaded will not go away until the service is restarted.

Also, I'm thinking about adding "test" and "draft" assemblies that will be short-lived. No need to load them and keep them forever. So I need to unload them. I did this many moons ago with `AppDomains` on .NET Platform, so what is new?

### Unloading Assemblies

> All of the source code is available [here](https://github.com/Seekatar/assemblyUnloadTest).

In the days of .NET Platform, to be able to unload an assembly we used [AppDomains](https://docs.microsoft.com/en-us/dotnet/api/system.appdomain). AppDomains are like subprocesses, in that memory is protected from other AppDomains. To use an object in another AppDomain, it has to be marshaled across the boundary.

With .NET Core, there is only one AppDomain, but there is a new [AssemblyLoadContext](https://docs.microsoft.com/en-us/dotnet/api/system.runtime.loader.assemblyloadcontext) (ALC) to allow loading and unloading of assemblies. Things are easier in that no marshaling is required, but there is a second edge to that sword. Unloading an `AssemblyLoadContext` is "cooperative," meaning unlike the forced unloading of an `AppDomain`, the `ALC` only unloads when everything is released.

What this means for using an `ALC` is that you must make sure no references to objects in the `ALC` are in another context, including the default. See [this from MS](https://docs.microsoft.com/en-us/dotnet/standard/assembly/unloadability#troubleshoot-unloadability-issues) for more details.

### The Road to Unloading

All the samples I found do something like "ExecuteAndUnload" from the [sample code](https://github.com/dotnet/samples/tree/main/core/tutorials/Unloading) that does everything in one method:

1. Load the assembly
2. Call a method in the assembly
3. Unload the assembly

This is fine, my scenario was like this:

1. Load the assembly
2. Get an object from the assembly
3. Return it to let others use that object for a time
4. Let them tell me when finished so that I can unload the assembly.

I created a sample app for testing out `ALC`s. The idea is to have it load assemblies and creates objects that can be called from main. Then after a time, I can call `Unload` to free all my assemblies.

Getting the object out is no problem. Making sure there are no references to it was a bit tricky. First I was using top-level statements for `Program.cs`, which I found that even if variables are scoped in braces, they never get garbage collected. I switched to using a class and static `Main`, but that had the same issue. Calling a method, however, did allow a variable to get collected when it was out of scope. And if a variable created by the context doesn't get garbage collected, the context can never be unloaded.

> In the sample I have a `DestructorTest` class I create in the switch statement, and within a method, and only the one in the method gets collected.

## The Solution: AssemblyManager

Working with `ALC`s is pretty easy. It has methods to load assemblies in various ways, and unload them.

```csharp
context.LoadFromAssemblyPath(fileName);
...
context.Unload();
```

My wrapper for the `ALC` does the load and unload of named contexts, and also allows the creation of objects in a context. Here's the method to load from a file. `CheckContext` checks to see if it has a context of that name, and creates it if needed. After the assembly is loaded, it's added to a collection that is used in `CreateInstance`

```csharp
public bool LoadFromAssemblyPath(string name, string fileName, string? contextName = null)
{
    contextName ??= FirstContextName;

    var context = CheckContext(contextName);

    var ret = context.LoadFromAssemblyPath(fileName);
    if (ret != null)
        context.LoadedAssemblies.Add(name, ret);
    return ret != null;
}
```

Here's the method to create an instance (error checking removed). This finds the named context, and assembly by name then creates an instance of the class.

```csharp
public TObj? CreateInstance<TObj>(string name, string? contextName, params object?[]? args) where TObj : class
{
    contextName ??= FirstContextName;
    if (_contexts.TryGetValue(contextName, out var context))
    {
        var assembly = context.LoadedAssemblies.Where(o => o.Key == name).Select(o => o.Value).FirstOrDefault();

        return Activator.CreateInstance(type, args) as TObj;
    }
}
```

The unload is pretty simple. Just find the context and call `Unload` on it. `_deadContext` is a `WeakReference` to the context that I used for diagnostics to see if the context was removed.

```csharp
public void Unload(string? contextName = null)
{
    contextName ??= FirstContextName;

    if (!_contexts.TryGetValue(contextName, out var context)) return;
    context.LoadedAssemblies = new(); // MUST do this or else ALC won't unload

    _contexts.Remove(contextName);

    _deadContext = new WeakReference(context); // create this to check if unloaded, if we care

    context.Unload();
}
```

## An Engine for Testing the Manager

`Engine` is a test class that drives the manager. It has methods to load a couple of assemblies (libA and libB) that have `ITest` implementations. In addition, it can use Rosyln to build assemblies in memory and load them into either the manager's first context (which is _not_ the `AssemblyLoadContext.Default`), or one called "Test".
It can then call methods on all the assemblies.

Here's a test run loading a and b into the first context (`__FirstContext__`) and calling `Message()` on them.

```text
ITest [16:38:02 INF] Default Context is 'Default'

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
a pressed
ITest [16:38:06 INF] Loading A into context that __FirstContext__ currently has 0 assemblies.

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
b pressed
ITest [16:38:07 INF] Loading B into context that __FirstContext__ currently has 1 assemblies.

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
c pressed
>>>> TestA 'From Program 9/4/2022 4:38:24 PM'
>>>> TestB 'From Program 9/4/2022 4:38:25 PM

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
d pressed
There are 2 contexts
  * 'Default' with 76 assemblies
  * '__FirstContext__' with 2 assemblies
    - libA, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null
    - libB, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null

```

In Visual Studio Debug->Windows->Modules, you can see that the modules are loaded.

![libA and libB loaded](/assets/images/2022-09-04-libs.png)

Using `u` in the sample will wipe out the `ITest` references, and call `Unload` on the context. You can wait for garbage collection to run, but the sample has a `g` command to do that. The first time you press `g` is will collect the `ITest` objects, which write to the console in their destructors.

```text
u pressed
ITest [16:22:47 INF] Unloading context __FirstContext__

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
g pressed
~~~~ AAAAAAAAAAAAAAAAAAAAAAAAAA!
~~~~ BBBBBBBBBBBBBBBBBBBBBBBBBBB!
```

At this point, if you look at the modules, you will still see `libA.dll` and `libB.dll` that's because now that the `ITest` instances are collected, another pass is required to see that the context itself can be collected. After pressing `g` a second time, the assemblies are gone.

![libA and libB loaded](/assets/images/2022-09-04-libs-gone.png)

Using capital letters in the test program loads the assembly into the "Test" context.

```text
b pressed
ITest [16:34:31 INF] Loading B into context that __FirstContext__ currently has 0 assemblies.

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
B pressed
ITest [16:34:33 INF] Loading B into context that Test currently has 0 assemblies.

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
c pressed
>>>> TestB 'From Program 9/4/2022 4:34:39 PM

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
C pressed
>>>> TestB 'From Program 9/4/2022 4:34:42 PM
```

Looking in Visual Studio, you'll see that the same assembly is loaded twice.

![two libBs loaded](/assets/images/2022-09-04-2libB.png)

Pressing `d` to dump the context, we see it loaded into different ones. Attempting to load `libB` into a context twice, will throw an exception.

```text
d pressed
There are 3 contexts
  * 'Default' with 77 assemblies
  * '__FirstContext__' with 1 assemblies
    - libB, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null
  * 'Test' with 1 assemblies
    - libB, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null
```

Pressing `2` will generate and load 100 assemblies.

```text
2 pressed
...
ITest [16:59:31 INF] Context currently has 96 assemblies
 [16:59:31 INF] Parsing text completed in 0.1 ms
 [16:59:31 INF] Compiling code completed in 8.1 ms
 [16:59:31 INF] Emitting completed in 2.9 ms
 [16:59:31 INF] Building assembly completed in 15.8 ms
ITest [16:59:31 INF] Loading ATest2-97 into context __FirstContext__.
ITest [16:59:31 INF] Context currently has 97 assemblies
 [16:59:31 INF] Parsing text completed in 0.1 ms
 [16:59:31 INF] Compiling code completed in 7.5 ms
 [16:59:31 INF] Emitting completed in 3.3 ms
 [16:59:31 INF] Building assembly completed in 16.2 ms
ITest [16:59:31 INF] Loading ATest2-98 into context __FirstContext__.
ITest [16:59:31 INF] Context currently has 98 assemblies
 [16:59:31 INF] Parsing text completed in 0.1 ms
 [16:59:31 INF] Compiling code completed in 7.9 ms
 [16:59:31 INF] Emitting completed in 3.2 ms
 [16:59:31 INF] Building assembly completed in 16.1 ms
ITest [16:59:31 INF] Loading ATest2-99 into context __FirstContext__.
ITest [16:59:31 INF] Context currently has 99 assemblies

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
c pressed
@@@@ ATest2 'From Program 9/4/2022 5:00:23 PM
@@@@ ATest2 'From Program 9/4/2022 5:00:23 PM
@@@@ ATest2 'From Program 9/4/2022 5:00:23 PM
@@@@ ATest2 'From Program 9/4/2022 5:00:23 PM
...
@@@@ ATest2 'From Program 9/4/2022 5:00:23 PM
@@@@ ATest2 'From Program 9/4/2022 5:00:23 PM
@@@@ ATest2 'From Program 9/4/2022 5:00:23 PM
@@@@ ATest2 'From Program 9/4/2022 5:00:23 PM

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
d pressed
There are 2 contexts
  * 'Default' with 85 assemblies
  * '__FirstContext__' with 100 assemblies
    - ATest2-0, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null
    - ATest2-1, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null
    - ATest2-2, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null
    - ATest2-3, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null
    - ATest2-4, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null
    - ATest2-5, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null
    - ATest2-6, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null
...
```

And the modules when loaded. Again two rounds of gc will clean them all up.

![big load of assemblies](/assets/images/2022-09-04-bigload.png)

## A Little Fun

You can also enter a mathematical expression for a variable `d` an assembly with that is generated, then when pressing `p` all loaded assemblies are called with 0-49 and plotted using [Ascii Chart C#](https://github.com/NathanBaulch/asciichart-sharp)

```text
Enter equation using 'd'
Sin(d/4)
 [17:07:56 INF] Parsing text completed in 0.2 ms
 [17:07:56 INF] Compiling code completed in 44.4 ms
 [17:07:56 INF] Emitting completed in 4.4 ms
 [17:07:56 INF] Building assembly completed in 57.9 ms
ITest [17:07:56 INF] Loading ATest1-0 into context __FirstContext__.
ITest [17:07:56 INF] Context currently has 0 assemblies

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
e pressed
Enter equation using 'd'
d*d
 [17:08:06 INF] Parsing text completed in 0.1 ms
 [17:08:06 INF] Compiling code completed in 14.7 ms
 [17:08:06 INF] Emitting completed in 3.2 ms
 [17:08:06 INF] Building assembly completed in 23.9 ms
ITest [17:08:06 INF] Loading ATest2-0 into context __FirstContext__.
ITest [17:08:06 INF] Context currently has 1 assemblies

Press a key: load(a), load(b), (u)nload, (c)all, (g)arbage (q)uit
p pressed
>>>> Chart for Sin(d/4)
  1.00 ┤    ╭───╮                    ╭───╮
  0.80 ┤   ╭╯   ╰╮                  ╭╯   ╰╮
  0.60 ┤  ╭╯     ╰╮                ╭╯     ╰╮
  0.40 ┤ ╭╯       ╰╮              ╭╯       ╰╮
  0.20 ┤╭╯         ╰╮            ╭╯         ╰╮
 -0.00 ┼╯           │           ╭╯           ╰╮
 -0.20 ┤            ╰╮         ╭╯             │
 -0.40 ┤             ╰╮        │              ╰╮        ╭
 -0.60 ┤              ╰╮      ╭╯               ╰╮      ╭╯
 -0.80 ┤               ╰─╮  ╭─╯                 ╰─╮  ╭─╯
 -1.00 ┤                 ╰──╯                     ╰──╯
>>>> Chart for d*d
 2401.00 ┤                                               ╭─
 2160.90 ┤                                             ╭─╯
 1920.80 ┤                                          ╭──╯
 1680.70 ┤                                       ╭──╯
 1440.60 ┤                                    ╭──╯
 1200.50 ┤                                ╭───╯
  960.40 ┤                            ╭───╯
  720.30 ┤                        ╭───╯
  480.20 ┤                  ╭─────╯
  240.10 ┤          ╭───────╯
    0.00 ┼──────────╯
```

## Summary

It took me a while to shake out all the little issues to get the AssemblyLoadContexts to unload properly, but think the AssemblyManager is pretty solid. I hope you found this useful.

## Links

- [MS Doc: AssemblyLoadContext Class](https://docs.microsoft.com/en-us/dotnet/api/system.runtime.loader.assemblyloadcontext)
- [MS Doc: How to use and debug assembly unloadability in .NET Core](https://docs.microsoft.com/en-us/dotnet/standard/assembly/unloadability)
- [MS Doc: Understanding System.Runtime.Loader.AssemblyLoadContext](https://docs.microsoft.com/en-us/dotnet/core/dependency-loading/understanding-assemblyloadcontext)
- [MS Sample Code for Unloading](https://github.com/dotnet/samples/tree/main/core/tutorials/Unloading) which is from the .NET Samples repo
- [Exploring the new Assembly unloading feature in .NET Core 3.0 by building a simple plugin system running on ASP.NET Core Blazor](https://stevenknox.net/exploring-assembly-unloading-in-net-core-3-0-by-building-a-simple-plugin-architecture/) by Steve Knox
- [Ascii Chart C#](https://github.com/NathanBaulch/asciichart-sharp)
