---
title: .NET 7's ProblemDetailsService
tags:
 - dotnet
 - problem-details
 - asp.net
excerpt: Experimenting with ASP.NET 7's ProblemDetailsService
cover: /assets/images/leaf2.jpg
comments: true
layout: article
key: unload-assembly
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## What are Problem Details?

ProblemDetails are an implementation of [RFC7807](https://tools.ietf.org/html/rfc7807), a standard for returning errors from an API.

The existing .NET [ProblemDetails](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.mvc.problemdetails) class conforms to that standard. ASP.NET Core also has a [Results.Problem](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.results.problem) method to return a `ProblemDetails` object from a controller.

You can handle getting ProblemDetails JSON back to the client in various ways. I explored several of them in [this repo](https://github.com/Seekatar/ioptions-logger-test#returning-problemdetails-from-a-controller). One of the best ones is to use the library from Kristian Hellang: [ProblemDetails](https://www.nuget.org/packages/Hellang.Middleware.ProblemDetails). (Andrew Lock's [blog post](https://andrewlock.net/handling-web-api-exceptions-with-problemdetails-middleware/) about it has pretty good directions (better than the README).)

## New Toys!

With the new ASP.NET 7 [ProblemDetailsService](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.iproblemdetailsservice), as described in this [MS blog post](https://devblogs.microsoft.com/dotnet/asp-net-core-updates-in-dotnet-7-preview-7/#new-problem-details-service), I thought everything will be built in and I could start deleted code (the best way to eliminate bugs). But, alas, some things still aren't quite there from what I can tell.

I want to be able to send a nice `ProblemDetails` object to the client with details about what went wrong. Ideally, be able to throw an exception that gets turned into `ProblemDetails`.

In .NET there's no exception like that. Also, the JSON returned to the caller isn't very useful. Here's the release-mode payload from throwing an exception that includes `ProblemDetails`. Not too useful

```json
{
  "type": "https://tools.ietf.org/html/rfc7231#section-6.6.1",
  "title": "An error occurred while processing your request.",
  "status": 500
}
```

If you turn on `UseDeveloperExceptionPage()` you get much more information. But this is not what you want to send to the client.

```json
{
    "type": "https://tools.ietf.org/html/rfc7231#section-6.6.1",
    "title": "ProblemDetailsTest.ProblemDetailsException",
    "status": 500,
    "detail": "Throwing ProblemDetailsException",
    "exception": {
        "details": "ProblemDetails:\r\n  Status: 500\r\n  Type: https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1\r\n  Title: Throwing ProblemDetailsException\r\n  Detail: My detail message, look for a and status of 500 and log level of Error\r\n  Extensions:\r\n    extension_value_int: 1232\r\n    extension_value_string: Some value\r\n    method_name: ThrowProblemDetails\r\nProblemDetailsTest.ProblemDetailsException: Throwing ProblemDetailsException\r\n   at ProblemDetailsTest.Controllers.ExceptionController.ThrowProblemDetails(Guid clientId, Int32 marketEntityId, LogLevel logLevel) in C:\\code\\problem-details-test\\src\\Controllers\\ExceptionController.cs:line 53\r\n   at lambda_method2(Closure, Object, Object[])\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ActionMethodExecutor.SyncActionResultExecutor.Execute(ActionContext actionContext, IActionResultTypeMapper mapper, ObjectMethodExecutor executor, Object controller, Object[] arguments)\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ControllerActionInvoker.InvokeActionMethodAsync()\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ControllerActionInvoker.Next(State& next, Scope& scope, Object& state, Boolean& isCompleted)\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ControllerActionInvoker.InvokeNextActionFilterAsync()\r\n--- End of stack trace from previous location ---\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ControllerActionInvoker.Rethrow(ActionExecutedContextSealed context)\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ControllerActionInvoker.Next(State& next, Scope& scope, Object& state, Boolean& isCompleted)\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ControllerActionInvoker.InvokeInnerFilterAsync()\r\n--- End of stack trace from previous location ---\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ResourceInvoker.<InvokeFilterPipelineAsync>g__Awaited|20_0(ResourceInvoker invoker, Task lastTask, State next, Scope scope, Object state, Boolean isCompleted)\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ResourceInvoker.<InvokeAsync>g__Awaited|17_0(ResourceInvoker invoker, Task task, IDisposable scope)\r\n   at Microsoft.AspNetCore.Mvc.Infrastructure.ResourceInvoker.<InvokeAsync>g__Awaited|17_0(ResourceInvoker invoker, Task task, IDisposable scope)\r\n   at Microsoft.AspNetCore.Routing.EndpointMiddleware.<Invoke>g__AwaitRequestTask|6_0(Endpoint endpoint, Task requestTask, ILogger logger)\r\n   at Microsoft.AspNetCore.Authorization.AuthorizationMiddleware.Invoke(HttpContext context)\r\n   at Swashbuckle.AspNetCore.SwaggerUI.SwaggerUIMiddleware.Invoke(HttpContext httpContext)\r\n   at Swashbuckle.AspNetCore.Swagger.SwaggerMiddleware.Invoke(HttpContext httpContext, ISwaggerProvider swaggerProvider)\r\n   at Microsoft.AspNetCore.Diagnostics.DeveloperExceptionPageMiddlewareImpl.Invoke(HttpContext context)",
        "headers": {
            "Accept": [
                "application/json"
            ],
            "Host": [
                "localhost:5138"
            ],
            "User-Agent": [
                "Mozilla/5.0 (Windows NT 10.0; Microsoft Windows 10.0.19044; en-US) PowerShell/7.3.1"
            ]
        },
        "path": "/api/throw/details/d106cf8e-3652-4914-b6e6-dbea785ffc13/1/4",
        "endpoint": "ProblemDetailsTest.Controllers.ExceptionController.ThrowProblemDetails (problem-details-test)",
        "routeValues": {
            "action": "ThrowProblemDetails",
            "controller": "Exception",
            "clientId": "d106cf8e-3652-4914-b6e6-dbea785ffc13",
            "marketEntityId": "1",
            "logLevel": "4"
        }
    }
}
```

## The Sample Code

> All of the source code for this blog is available [here](https://github.com/Seekatar/problem-details-test).

I created a sample to explore the .NET 7 features. It's an ASP.NET 7 webapi with the new features enabled. There are just a few lines of code you need to add to `program.cs`

```csharp
builder.Services.AddProblemDetails();
...
var app = builder.Build();
...
app.UseExceptionHandler();

// this returns problemDetails if caller sets accept to application/json for responses with status codes between 400 and 599 that do not have a body
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
    app.UseDeveloperExceptionPage();
```

That all works, giving a JSON result if the caller sets the `Accept` header to `application/json` as shown above. I have two requirements that aren't met by the default implementation.

1. Send the client a `ProblemDetails` object I created, deep anywhere in my code (by throwing an exception)
2. Control logging of the `ProblemDetails` exception

To solve these problems I created a `ProblemDetailsException` that simply wraps a `ProblemDetails` and `LogLevel` and middleware to catch the exception and use the new `ProblemDetailsService.WriteAsync` method to write the `ProblemDetails` to the response. Nothing too exciting here.

For testing, I created two endpoints: one that just throws a `NotImplementedException` and the new exception.

When starting the sample app, you can pass in a number that's a bit flag to turn on various features. `dotnet run -- <0-7>`

```csharp
[Flags]
enum ProblemDetailsEnum
{
    Vanilla = 0,                // just AddProblemDetails, UseExceptionHandler, and UseDeveloperExceptionPage
    DeveloperExceptionPage = 1, // turn on UseDeveloperExceptionPage
    CustomProblemDetails = 2,   // use CustomizeProblemDetails when calling AddProblemDetails to see what that affects
    UseMyMiddleware = 4         // turn on my middleware
}
```

## Testing the Sample

There's a little PowerShell script to call the test endpoints and dump the returned object. It also calls a non-existent endpoint to see what the default behavior is.

### Vanilla (0)

Both endpoints that throw returned this:

```json
{
    "type": "https://tools.ietf.org/html/rfc7231#section-6.6.1",
    "title": "An error occurred while processing your request.",
    "status": 500
}
```

The 404 returned this and will return this for all the other tests.

```json
{
    "type": "https://tools.ietf.org/html/rfc7231#section-6.5.4",
    "title": "Not Found",
    "status": 404
}
```

### DeveloperExceptionPage (1)

Turning on the `DeveloperExceptionPage` dumps, including the entire call stack (truncated here). The exception.details does show the `ToString()` of the exception, but not very useful to a caller.

```json
{
    "type": "https://tools.ietf.org/html/rfc7231#section-6.6.1",
    "title": "ProblemDetailsTest.ProblemDetailsException",
    "status": 500,
    "detail": "Throwing ProblemDetailsException",
    "exception": {
        "details": "ProblemDetails:\r\n  Status: 500\r\n  Type: https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1\r\n...",
        "headers": {
            "Accept": [
                "application/json"
            ],
            "Host": [
                "localhost:5138"
            ],
            "User-Agent": [
                "Mozilla/5.0 (Windows NT 10.0; Microsoft Windows 10.0.19044; en-US) PowerShell/7.3.1"
            ]
        },
        "path": "/api/throw/details/abe0e20f-b8b2-4759-8e77-567af36554b0/1/4",
        "endpoint": "ProblemDetailsTest.Controllers.ExceptionController.ThrowProblemDetails (problem-details-test)",
        "routeValues": {
            "action": "ThrowProblemDetails",
            "controller": "Exception",
            "clientId": "abe0e20f-b8b2-4759-8e77-567af36554b0",
            "marketEntityId": "1",
            "logLevel": "4"
        }
    }
}
```

### CustomProblemDetails (2)

I wasn't clear on what adding this to `AddProblemDetails` does. They say it controls the creation of the `ProblemDetails` before it's written out. I see the type during it.

```json
{
    "type": "set in customproblemdetails",
    "title": "An error occurred while processing your request.",
    "status": 500
}
```

### DeveloperExceptionPage + CustomProblemDetails (3)

This is the same as DeveloperExceptionPage (1) above, but the `type` in the payload is set to the value I set in `CustomProblemDetails`.

### MyMiddleware (4)

This is just my middleware, and yay!, we get nice output when throwing the `ProblemDetailsException`. You can now send the caller nice details about an error. In addition the a `ProblemDetails` in the exception, it also includes a log level so you can control what level to log the exception (if at all). The default implementation logs everything at the `Error`.

```json
{
    "type": "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1",
    "title": "Throwing ProblemDetailsException",
    "status": 500,
    "detail": "My detail message, look for a and status of 500 and log level of Error",
    "extension_value_int": 1232,
    "extension_value_string": "Some value",
    "method_name": "ThrowProblemDetails"
}
```

Throwing the not implemented exception is pretty much the same as the default.

```json
{
    "type": "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1",
    "title": "Unhandled exception of type NotImplementedException",
    "status": 500,
    "detail": "Throwing NotImplementedException"
}
```

### DeveloperExceptionPage + MyMiddleware (5)

This loses my middleware and returns the same as DeveloperExceptionPage (1) above.

### CustomProblemDetails + MyMiddleware (6)

This is just like MyMiddleware (4) above, but the `type` is set to the value I set in `CustomProblemDetails`.

### DeveloperExceptionPage + CustomProblemDetails + MyMiddleware (7)

Same as DeveloperExceptionPage + CustomProblemDetails (3) above.

## Summary

This was a fun playing with the new feature, but a little disappointed with the documentation not being able to easily send your own `ProblemDetails` object (that's been around since .NET Core 2.1). But adding an exception and middleware you can get something pretty useful, which is what Hellang's NuGet package does.

## Links

- [MS Doc: ProblemDetails](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.mvc.problemdetails)
- [ProblemDetailsService](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.iproblemdetailsservice)
- [RFC7807](https://tools.ietf.org/html/rfc7807)
- [Andrew Lock: Handling Web API Exceptions with ProblemDetails middleware](https://andrewlock.net/handling-web-api-exceptions-with-problemdetails-middleware/) talks about using Hellang's NuGet package for ProblemDetails
