---
title: ASP.NET Authentication & Authorization
tags:
 - dotnet
 - authentication
 - authorization
 - forwarding
 - asp.net
excerpt: Using Forwarding in ASP.NET Authentication
cover: /assets/images/super-natural-1639059.jpg
comments: true
layout: article
key: aspnet-auth
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

In [my previous](https://seekatar.github.io/2023/07/01/aspnet-auth.html) post, I talked about configuring authentication and authorization in ASP.NET Core. One of the issues with that code was that when there were multiple authentication schemes, all of them were tried, even though only one would authenticate the users. In the trivial sample code, it didn't matter, but in my real work-related code it was a problem.

In the real-world example, I had Basic authn, home-rolled JWT authn, and Azure Active Directory JWT authn. Adding the two JWT handlers worked, but when an endpoint was called that passed in our home-rolled JWT, the MSAL (Microsoft Authentication Library) handler would try to parse it and fail and log several error messages. ASP.NET is very configurable, so I knew that I just had to poke around to figure out the right way to do it.

## Steps in ASP.NET Authentication

Forwarding
Authentication
401
403?

Forwarding

Why do I have to add the Scheme to A AND B?

## Changes to the Sample Code

After adding the forward, and always using a default authn scheme, I did have to make a few tweaks to the tests and controller.

## Summary

By using a forwarder, I could tell ASP.NET specifically which authn scheme it should use, instead of letting it try all of them. This is a bit more efficient, and when using Azure JWTs, avoided error messages in the logs.

## Links

- [Source code](https://github.com/Seekatar/ioptions-logger-test)
- [MS: Authorize with a specific scheme in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/limitingidentitybyscheme)
- [MS:Policy schemes in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/policyschemes)
- [MS: Overview of ASP.NET Core authentication]([Title](https://learn.microsoft.com/en-us/aspnet/core/security/authentication))
- [MS: Introduction to authorization in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/introduction)
- [MS: AuthenticationHandler](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.authentication.authenticationhandler-1?view%253Daspnetcore-7.0)
