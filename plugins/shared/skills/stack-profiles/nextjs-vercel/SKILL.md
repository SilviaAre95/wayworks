---
name: nextjs-vercel
description: "Stack context for Next.js + Vercel projects — App Router, RSC, Prisma, Tailwind, and Vercel deployment conventions"
user-invocable: false
paths: "next.config.*,app/**/page.tsx,app/**/layout.tsx,vercel.json"
---

# Stack Profile: Next.js + Vercel

This profile is automatically loaded when working in a Next.js project deployed to Vercel.

## Architecture Conventions

- **Next.js 16+** with App Router (not Pages Router)
- **React Server Components** by default; `"use client"` only when needed
- **Prisma** for database access with PostgreSQL
- **Tailwind CSS** for styling
- **NextAuth** or similar for authentication
- **Zod** for validation at system boundaries

## File Structure

```
app/
├── (auth)/           # Route groups for layout scoping
│   ├── login/
│   └── register/
├── api/              # API routes
│   └── resource/
│       └── route.ts  # GET, POST, PUT, DELETE handlers
├── layout.tsx        # Root layout
└── page.tsx          # Home page
src/
├── components/       # Shared React components
├── lib/              # Utilities, config, Prisma client
└── server/           # Server-only code (services, auth)
prisma/
└── schema.prisma
```

## Key Patterns

- Route handlers export named functions: `export async function GET(request: Request)`
- Server actions for mutations: `"use server"` in action files
- Metadata API for SEO: `export const metadata = { ... }` or `generateMetadata()`
- Loading UI: `loading.tsx` for Suspense boundaries
- Error UI: `error.tsx` for error boundaries
- Proxy: `proxy.ts` at project root exporting `proxy(request)` for auth/redirects. Node.js runtime only — a `runtime` export in this file is a build error. Never rely on it alone for auth: a matcher change silently drops coverage, so authorize inside each Server Function too
- Upgrading from 15: `middleware.ts` is deprecated but still runs. Rename it with `npx @next/codemod@canary middleware-to-proxy .` (renames the file and the exported function); `skipMiddlewareUrlNormalize` becomes `skipProxyUrlNormalize`

## TypeScript & Code Style

- Strict TypeScript everywhere — no `any` unless truly unavoidable (document why)
- Prefer `const` over `let`, never `var`; named exports over default exports
- Early returns to reduce nesting
- Zod for runtime validation at system boundaries; React Hook Form + Zod for forms
- No barrel files (`index.ts` re-exports) unless the package explicitly needs a public API
- Tailwind CSS for styling — no CSS modules, no styled-components
- Colocate single-use components with their route; shared components in `src/components/`

## Vercel-Specific

- Environment variables: set in Vercel dashboard, not `.env` in production
- Edge functions: use `export const runtime = 'edge'` sparingly (route handlers and pages only — not available in `proxy.ts`)
- ISR: `revalidate` export for static pages that update
- Image optimization: use `next/image`, Vercel handles the CDN
- Analytics: `@vercel/analytics` for web vitals
- Cron: `vercel.json` crons for scheduled tasks

## Database

- Use Prisma with connection pooling (PgBouncer or Prisma Accelerate)
- `DATABASE_URL` with `?pgbouncer=true&connection_limit=1` for serverless
- Run migrations in CI, not at deploy time

## Performance

- Minimize client JavaScript — keep `"use client"` components small
- Use `Suspense` boundaries for streaming
- Prefetch navigation with `<Link>` (automatic in App Router)
- Avoid waterfalls: parallel data fetching with `Promise.all`
