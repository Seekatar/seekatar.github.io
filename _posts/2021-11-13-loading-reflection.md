---
author: seekatar
title: Registering with Reflection
tags:
 - dependency injection
 - reflection
 - C#
 - code
synopsis: Register classes with DI for ASP.NET Core/5/6
comments: true
---

## Problem

I have a bunch of classes that need to be registered with the ASP.NET service collection, but don't want to manually add them.

## Solution

To solve this I'm going to use Reflection to get all the classes I want to register by looking at specific criteria of the classes.

First I need to find all the classes that meet the criteria. Here's a method that gets all the types that are matched with a `Predicate` that is passed into it by looking at all the types loaded in the current app domain.

```C#
public static List<Type> GetTypesInLoadedAssemblies(Predicate<Type> predicate, string assemblyPrefix = "")
{
    return AppDomain.CurrentDomain.GetAssemblies()
                        .Where(o => o.GetName().Name?.StartsWith(assemblyPrefix, StringComparison.OrdinalIgnoreCase) ?? false)
                        .SelectMany(s => s.GetTypes())
                        .Where(x => predicate(x))
                        .ToList();
}
```

To get all the classes that implement an interface and register them, I can call it like this.

```C#
var types = GetTypesInLoadedAssemblies((type) => typeof(IMyInterface).IsAssignableFrom(type) && !type.IsInterface && !type.IsAbstract);

foreach ( var type in types)
{
    services.AddTransient(typeof(IMyInterface), type);
}
```

This works fine when all this code and the classes you want to register are loaded into your app domain, but that may not be the case if you haven't referenced anything in the assembly yet to load it. To get around that you can load the assemblies by hand. No doubt you have a good naming convention for your assemblies so you can pass a `searchPattern` like `MyCompany*.dll` to load all your assemblies so that `AppDomain.CurrentDomain.GetAssemblies` will be able to find all your classes.

```C#
public static IEnumerable<Assembly> GetAssemblies(string searchPattern)
{
    var assemblies = Directory.EnumerateFiles(
        Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location) ?? throw new InvalidOperationException(),
        searchPattern, SearchOption.TopDirectoryOnly)
                .Select(Assembly.LoadFrom)
                .ToList();

    return assemblies;
}
```

I first used this technique to find all `IInstaller` instances, instantiate them and call `InstallServices` on each one. Since then I have used it in other cases where I want to do something with a bunch of classes such as registering them with a factory, etc.
