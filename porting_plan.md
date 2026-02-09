# AuthScreen Porting Plan

To integrate the existing `AuthScreen` design into Next.js:

1.  **Move Assets**: Copy `style.css` content to a CSS module or global CSS (already have globals, but `style.css` has specific animations).
    - _Decision_: Create `src/styles/auth.css` and import it in the Auth Layout.
    - Copy images/shapes if any (none in file list, just CSS shapes).

2.  **Create Components**:
    - `src/components/auth/AuthLayout.tsx`: Wrapper div with `auth-wrapper`.
    - `src/components/auth/LoginForm.tsx`: The "Sign In" panel.
    - `src/components/auth/RegisterForm.tsx`: The "Sign Up" panel.

3.  **Page Implementation**:
    - `src/app/login/page.tsx`: Renders the Auth Components.
    - Implement the toggle logic (`sign-up-mode` class) using React state instead of vanilla JS `querySelector`.

4.  **Wire Up Logic**:
    - Connect forms to `supabase.auth.signInWithPassword` and `signUp`.
    - Handle loading states and errors (toast notifications).

5.  **Refactor CSS**:
    - The existing `style.css` uses `.auth-wrapper` and global classes. I will preserve this structure but ensure it doesn't conflict with other pages.
