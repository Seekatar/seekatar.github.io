---
title: Using Forwarding in ASP.NET Authentication
tags:
 - dotnet
 - authentication
 - authorization
 - forwarding
 - asp.net
excerpt: Avoiding error messages when multiple authentication schemes are configured
cover: /assets/images/black-n-green-1177322.jpg
comments: true
layout: article
key: aspnet-auth
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

In [my previous](https://seekatar.github.io/2023/07/01/aspnet-auth.html) post, I talked about configuring authentication and authorization in ASP.NET Core. One of the issues with that sample code was that with multiple authentication schemes, all of them were tried, even though only one would authenticate the user. It didn't matter in the trivial sample code, but it was a problem in my work-related code.

For work, I had Basic authentication, home-rolled JWT authentication, and Azure Active Directory JWT authentication. Everything worked, but when an endpoint was called that passed in our home-rolled JWT, the MSAL (Microsoft Authentication Library) JWT handler would try to parse it, fail, and log several error messages. ASP.NET is very configurable, so I knew that I just had to poke around to figure out how to avoid those error messages.

In this follow-up post, I'll talk about how I solved the problem using a ForwardDefaultSelector.

## The ForwardDefaultSelector Option

If an authentication scheme isn't specified in the Policy, or in the `[Authorize]` on a controller (or method), ASP.NET will call _all_ the authentication schemes. By configuring a ForwardDefaultSelector, you can determine what default scheme ASP.NET should use for a Request.

To do this, I called `AddPolicyScheme` while configuring authentication. It takes a `PolicySchemeOptions` to configure it, which has the `ForwardDefaultSelector` Func I'm interested in. (That class has various other string properties perhaps the topic of another post.)

For the sample, I set it to a lambda that checks the suffix in the custom header to determine which scheme should authenticate this Request. If the header is missing, or the suffix is not A, B, or C, then `SchemeA` is used as the default as shown below:

```csharp
var user = context.Request.Headers["X-Test-User"].ElementAtOrDefault(0);
var scheme = SchemeA; // default
if (user is not null && user.StartsWith("User") && user.Length > 4 && user[4] is >= 'A' and <= 'C')
{
    scheme = $"Scheme{user[4..]}";
}
Console.WriteLine($"ForwardSelectorFromUser returning {scheme}");
return scheme;
```

As I mentioned above, my work code was a bit more complicated. In its forwarder, I used the `Authorization` header to determine if it was `Basic` or `Bearer` authentication. If it was `Basic`, I'd return the scheme that handled it. Otherwise, I decoded the JWT to look at the `issuer` to determine which of the two JWT schemes should authenticate the request.

## Changes to the Sample Code

`Program.cs` has some housekeeping changes to allow a parameter run with forwarding, a default scheme, or without a default scheme.

When configuring authentication in `Program.cs`, I now pass the name of a new scheme as the default. This new scheme is added with `AddPolicyScheme`, and has its `ForwardDefaultSelector` is set to the lambda above. The remainder of the code is the same as before.

```csharp
builder.Services
    .AddAuthentication(SchemeForwarding)
    .AddPolicyScheme(SchemeForwarding, SchemeForwarding, options =>
    {
        options.ForwardDefaultSelector = (context) =>
        {
            var user = context.Request.Headers["X-Test-User"].ElementAtOrDefault(0);
            var scheme = SchemeA; // default
            if (user is not null && user.StartsWith("User") && user.Length > 4 && user[4] is >= 'A' and <= 'C')
            {
                scheme = $"Scheme{user[4..]}";
            }
            Console.WriteLine($"ForwardSelectorFromUser returning {scheme}");
            return scheme;
        };
    })
    // Same as before 
    .AddScheme<MyAuthenticationSchemeOptions, CustomAuthenticationHandler>(SchemeA, options => options.Name = NameClaimA)
    .AddScheme<MyAuthenticationSchemeOptions, CustomAuthenticationHandler>(SchemeB, options => options.Name = NameClaimB)
    .AddScheme<MyAuthenticationSchemeOptions, CustomAuthenticationHandler>(SchemeC, options => options.Name = NameClaimC);
```

No changes were needed for authorization configuration.

## Testing

Running the sample with the old method of a default of Scheme and _not_ forwarding (`./run.ps1 -DefaultAuthScheme SchemeA`) then calling `/any` with `UserA`, all three schemes take a crack at authenticating as shown in the log output:

```text
>>>> /api/auth/any
SchemeA was authenticated. Set claims on UserA: name = 'A', role = 'A'
SchemeB returning NoResult on UserA
SchemeC returning NoResult on UserA
GetAuthAnyRole
    Name claim: A
    Role: A
```

To run the sample with `ForwardDefaultSelector`, use `./run.ps1 watch -DefaultAuthScheme forward`. Now, only `SchemeA` is called to authenticate the `UserA`'s suffix is `A`:

```text
>>>> /api/auth/any
ForwardSelectorFromUser returning SchemeA
SchemeA was authenticated. Set claims on UserA: name = 'A', role = 'A'
GetAuthAnyRole
    Name claim: A
    Role: A
```

Similarly, when using an invalid `UserQ`, the old code would try all three schemes, all three fail authentication, and are "challenged".

```text
>>>> /api/auth/any
SchemeA returning NoResult on UserQ
SchemeB returning NoResult on UserQ
SchemeC returning NoResult on UserQ
AuthenticationScheme: SchemeA was challenged.
AuthenticationScheme: SchemeB was challenged.
AuthenticationScheme: SchemeC was challenged.
```

With the forwarder, only `SchemeA` is tried since it is the default scheme.

```text
>>>> /api/auth/any
ForwardSelectorFromUser returning SchemeA
SchemeA returning NoResult on UserQ
ForwardSelectorFromUser returning SchemeA
AuthenticationScheme: SchemeA was challenged.
```

## Summary

By using a `ForwardDefaultSelector`, I could tell ASP.NET specifically which authentication scheme it should use based on headers in the Request, instead of letting it try all of them. This is a bit more efficient, and when using Azure JWTs, avoided error messages in the logs.

## Links

- [My previous post: ASP.NET Authentication & Authorization](https://seekatar.github.io/2023/07/01/aspnet-auth.html)
- [Source code](https://github.com/Seekatar/ioptions-logger-test)
- [MS:Authorize with a specific scheme in ASP.NET Core/Use multiple authentication schemes](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/limitingidentitybyscheme?view=aspnetcore-7.0#use-multiple-authentication-schemes) has a better example of forwarding near the end.
- [MS: Authorize with a specific scheme in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/limitingidentitybyscheme)
- [MS:Policy schemes in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/policyschemes) talks about forwarding, with a trivial example.
- [MS: Overview of ASP.NET Core authentication]([Title](https://learn.microsoft.com/en-us/aspnet/core/security/authentication))
- [MS: Introduction to authorization in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/introduction)
- [MS: AuthenticationHandler](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.authentication.authenticationhandler-1?view%253Daspnetcore-7.0)
