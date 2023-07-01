---
title: ASP.NET Authentication & Authorization
tags:
 - dotnet
 - authentication
 - authorization
 - asp.net
excerpt: Exploring ASP.NET Auth
cover: /assets/images/leaf2.jpg
comments: true
layout: article
key: aspnet-auth
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

Recently I needed to add multiple JWT as well as Basic authentication to a project. It seems simple, but I did run into some issues when configuring ASP.NET security, so I decided to take a deeper dive into configuring it and share what I learned here.

For the case mentioned above, I had a custom JWT provider, Azure Active Directory (AAD) providing JWTs, and Basic authentication all in the same application. In addition, some of the APIs required working with either Basic and AAD JWT authentication. This blog post will focus on the configuration of the authentication and authorization for a simple API and not concerned about securely authenticating a user. In another post I'll talk about issues getting the two JWT providers to work together.

## Terminology

`Authentication (AuthN)`
: The process of determining who a user is. There are various ways this is done, such as with an encoded username and password (Basic) or some kind of secure token provided by a third party (e.g Google, Okta, Auth0, or Microsoft).

`Authorization (AuthZ)`
: The process of determining what a user is allowed to do. This is often done by assigning roles or groups to a user and then checking if the user has the required role to perform an action.

`Scheme`
: An arbitrary name you give to an authentication method in your app. In this example I have `SchemaA`, `SchemaB`, and `SchemaC`.

`Policy`
: A policy is a way of authorizing a user. Policies in ASP.NET have various criteria for authorizing a user, such as requiring a role, or certain values for claims, or a specific authentication scheme. This example configures various policies for the API.

`Role`
: A role is an attribute of an authenticated user often used for authorization. Most of the policies in this example require a role.

In this sample, I'm focused on configuring the authentication and authorization for a simple ASP.NET API and not concerned about securely authenticating a user. The implementation of the `AuthenticationHandler` just uses some custom headers for the username and roles. In a real application you'd use something like JWTs (JSON Web Tokens) for authentication.

## The Test

For testing I created an API and three authentication schemes to be able to test various scenarios such as requiring two authorizations, or requiring one of two authorizations.

### Auth Setup

| Name | AuthZ           | Description         |
| ---- | --------------- | ------------------- |
| A    | Always succeeds | Policy included     |
| B    | Always succeeds | Policy not included |
| C    | Always fails    |

### Test Cases

This sample focused on configuring the authentication and authorization for a simple API so the sample `AuthenticationHandler` just uses some custom headers for the username and roles.

| API           | Attribute                                                        | Expected Result                                 |
| ------------- | ---------------------------------------------------------------- | ----------------------------------------------- |
| auth/none     | None                                                             | OK for all                                      |
| auth/a        | `[Authorize(PolicyA)]`                                           | OK for A                                        |
| auth/b-scheme | `[Authorize(Policy = PolicyB, AuthenticationSchemes = SchemeB)]` | OK for B                                        |
| auth/a-and-b  | `[Authorize(PolicyA)][Authorize(PolicyB)]`                       | OK when have both A and B                       |
| auth          | `[Authorize]`                                                    | 500 since no default policy                     |
| auth/b        | `[Authorize(PolicyB)]`                                           | 500, Error no default policy and none specified |
| auth/c        | `[Authorize(PolicyC)]`                                           | 403, Unauthorized                               |
| auth/a-or-b   | `[Authorize(PolicyAOrB)]`                                        | OK for A or B                                   |

## The AuthenticationHandler

Here's the `AuthenticationHandler` I used for this sample. For the AuthN, it checks that the username from a custom header matches the configured name of this handler. This doesn't do the authorization, but it does add the roles from another custom header to the claims. The claims will used by ASP.NET to do the authorization.

```csharp
protected override Task<AuthenticateResult> HandleAuthenticateAsync()
{
    var user = Context.Request.Headers["X-Test-User"];
    if (!(user.ElementAtOrDefault(0)?.Equals($"User{Options.Name}", StringComparison.OrdinalIgnoreCase) ?? false))
        return Task.FromResult(AuthenticateResult.Fail($"'{user.ElementAtOrDefault(0)}' was not 'User{Options.Name}'"));

    var claims = new List<Claim>
    {
        new Claim(ClaimTypes.Name, Options.Name),
    };

    var role = Context.Request.Headers["X-Test-Role"];
    foreach (var rstring in role)
    {
        if (rstring is null) continue;
        foreach (var r in rstring.Split(","))
            claims.Add(new Claim(ClaimTypes.Role, r));
    }
    var identity = new ClaimsIdentity(claims, ClaimTypes.Name);
    var principal = new ClaimsPrincipal(identity);
    return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, ClaimTypes.Name)));
}
```

## Configuring Authentication

In the startup code, you call `AddAuthentication` to add schemes. In this case I add three implementations of `MyAuthenticationSchemeOptions` with different names. You usually see a string passed into `AddAuthentication` which is the default scheme that will be used if you don't specify one when setting up authorization policies. In this test I don't have a default scheme so I have to specify the scheme in the policy. If you only have one scheme, with .NET 7 it will use that as the default automatically (which is a breaking change from .NET 6 as described [here](https://learn.microsoft.com/en-us/dotnet/core/compatibility/aspnet-core/7.0/default-authentication-scheme))

```csharp
builder.Services
    .AddAuthentication() // No default scheme passed in
    .AddScheme<MyAuthenticationSchemeOptions, CustomAuthenticationHandler>(SchemeA, options => options.Name = NameClaimA )
    .AddScheme<MyAuthenticationSchemeOptions, CustomAuthenticationHandler>(SchemeB, options => options.Name = NameClaimB )
    .AddScheme<MyAuthenticationSchemeOptions, CustomAuthenticationHandler>(SchemeC, options => options.Name = NameClaimC );
```

## Configuring Authorization

In your startup code, you call `AddAuthorization` and configure your policies, usually right after configuring authentication.

```csharp
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(PolicyA, policy =>
        {
            // Require authenticated user on SchemeA and RoleA
            policy.AddAuthenticationSchemes(SchemeA)
                  .RequireAuthenticatedUser()
                  .RequireRole(RoleA);
        });
    options.AddPolicy(PolicyB, policy =>
        {
            // Require authenticated user and RoleA. Note no scheme specified.
            policy.RequireAuthenticatedUser()
                  .RequireRole(RoleB);
        });
    options.AddPolicy(PolicyAorB, policy =>
        {
            // Require authenticated user on SchemeA or SchemeB with RoleA or RoleB
            policy.RequireAuthenticatedUser()
                  .AddAuthenticationSchemes(SchemeA, SchemeB)
                  .RequireRole(RoleA, RoleB);
        });
    options.AddPolicy(PolicyC, policy => {
            // Require authenticated user (no scheme specified)
            policy.RequireAuthenticatedUser();
        });
});
```

## The Test Project

## Adding Authentication

```csharp
```

## Summary


## Links

