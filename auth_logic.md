# Authentication & Authorization Logic - Vertex Digital Group

This document outlines the security strategy for the Next.js 14+ application, ensuring strict Role-Based Access Control (RBAC) using Supabase Auth and Next.js Middleware.

## 1. Role Hierarchy

The platform uses the following role hierarchy in `public.profiles`:

- **`super_admin`**: Top-level access (User Management, Staff Analytics, promoting users).
- **`sales`**: Access to Staff Dashboard, Order Claiming, Client Communication.
- **`team`**: Access to Staff Dashboard, Order Execution (Milestone updates).
- **`client`**: Default role. Access to Client Portal, Ordering, My Projects.

## 2. Next.js Middleware (`src/middleware.ts`)

The middleware acts as the first line of defense, running on every request to protected routes.

### Logic Flow:

1. **Intercept Request**: Check if the path starts with `/admin`, `/dashboard`, or `/portal`.
2. **Refresh Session**: Call `supabase.auth.getSession()` to ensure the user is logged in.
3. **Redirect Unauthenticated**: If no session exists, redirect to `/login`.
4. **RBAC Check**:
   - Retrieve the user's role from the `public.profiles` table (cached in metadata or fetched).
   - **`/admin/*`**: Allow only if `role === 'super_admin'`.
   - **`/dashboard/*`**: Allow if `role` is `sales`, `team`, or `super_admin`.
   - **`/portal/*`**: Allow if `role === 'client'`.
5. **Unauthorized Redirect**: If a user tries to access a route their role doesn't support, redirect them to their home dashboard.

### Example Middleware Snippet

```typescript
import { createMiddlewareClient } from "@supabase/auth-helpers-nextjs";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();
  const supabase = createMiddlewareClient({ req, res });
  const {
    data: { session },
  } = await supabase.auth.getSession();

  // 1. Protected Routes Pattern
  if (
    req.nextUrl.pathname.startsWith("/admin") ||
    req.nextUrl.pathname.startsWith("/dashboard") ||
    req.nextUrl.pathname.startsWith("/portal")
  ) {
    // 2. Auth Check
    if (!session) {
      return NextResponse.redirect(new URL("/login", req.url));
    }

    // 3. Role Check (Fetch from DB or Custom Claims)
    // Note: For performance, it's best to store role in app_metadata or fetch efficiently.
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", session.user.id)
      .single();

    const role = profile?.role || "client";

    // Admin Routes
    if (req.nextUrl.pathname.startsWith("/admin") && role !== "super_admin") {
      return NextResponse.redirect(new URL("/portal", req.url)); // or Forbidden page
    }

    // Staff Dashboard
    if (
      req.nextUrl.pathname.startsWith("/dashboard") &&
      !["super_admin", "sales", "team"].includes(role)
    ) {
      return NextResponse.redirect(new URL("/portal", req.url));
    }
  }

  return res;
}
```

## 3. Client-Side Protection (Hooks)

For fine-grained control within components (e.g., hiding the "Claim Order" button for typical clients), we will use a custom hook `useProfile`.

### `useProfile` Hook

```typescript
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

export function useProfile() {
  const [profile, setProfile] = useState(null);

  useEffect(() => {
    async function fetchProfile() {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (user) {
        const { data } = await supabase
          .from("profiles")
          .select("*")
          .eq("id", user.id)
          .single();
        setProfile(data);
      }
    }
    fetchProfile();
  }, []);

  return {
    profile,
    isAdmin: profile?.role === "super_admin",
    isStaff: ["super_admin", "sales", "team"].includes(profile?.role),
  };
}
```

## 4. Redirect After Login

When the user successfully logs in using the existing `AuthScreen` form logic (wired to Supabase), the `onAuthStateChange` event will trigger a check:

```javascript
supabase.auth.onAuthStateChange(async (event, session) => {
  if (event === "SIGNED_IN") {
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", session.user.id)
      .single();

    if (profile.role === "super_admin") window.location.href = "/admin";
    else if (["sales", "team"].includes(profile.role))
      window.location.href = "/dashboard";
    else window.location.href = "/portal";
  }
});
```
