# Staff Frontend Developer Interview Questions & Answers

---

## System Design (Frontend-Focused)

### Q1: Design a large-scale single-page application — for example, design Twitter's feed

**Example Answer:**

"I'd start by identifying the core requirements: infinite scroll feed, real-time updates, media-heavy content, and high read traffic. I'd use React with a component library, React Query for server state, and a virtualized list (like TanStack Virtual) to handle thousands of feed items without DOM bloat. For real-time updates I'd use WebSockets or SSE to push new tweets rather than polling. I'd split the app into feature-based modules with lazy loading so the initial bundle is small. CDN-delivered assets and aggressive image optimization (WebP, lazy loading images) would handle the media load."

**Key Bullets:**
- Virtualized lists for large data sets (TanStack Virtual, react-window)
- React Query or SWR for server state, caching, and background refetching
- WebSockets or SSE for real-time push instead of polling
- Code splitting by route and feature to minimize initial bundle
- CDN + image optimization (WebP, lazy load, responsive images)
- Skeleton screens for perceived performance

---

### Q2: How would you architect a micro-frontend system?

**Example Answer:**

"I'd evaluate whether micro-frontends are actually needed — they add significant complexity and are best justified when you have multiple teams owning distinct product areas that need to deploy independently. I'd use Module Federation (Webpack 5) to allow separate apps to share dependencies and compose at runtime. Each team owns a vertical slice — routing, build pipeline, deployment. A shell app handles top-level routing and loads remote modules. Shared design system components live in a separate package consumed by all teams. The hardest part is versioning shared dependencies and avoiding bundle duplication."

**Key Bullets:**
- Only adopt micro-frontends if team/org boundaries justify the complexity
- Module Federation for runtime composition and shared dependencies
- Shell app owns routing, auth, and global layout
- Each remote owns its own build, deploy, and release cycle
- Shared design system and utilities as versioned packages
- Cross-app communication via custom events or a shared event bus
- Risk: dependency version mismatches, increased infra overhead

---

### Q3: How do you structure a monorepo for a large frontend codebase?

**Example Answer:**

"I'd use Turborepo or Nx for task orchestration with remote caching. The repo would be split into `apps/` (deployable products) and `packages/` (shared libraries like UI, utils, config). Each package has its own TypeScript config, tests, and build output. Turborepo's pipeline ensures packages build in the right order and caches unchanged outputs. Lint and type-check run at the package level so CI only runs what changed. The key discipline is keeping packages loosely coupled — avoid circular dependencies and treat each package like an external library."

**Key Bullets:**
- Turborepo or Nx for orchestration, caching, and affected-only CI
- `apps/` for deployables, `packages/` for shared code
- Strict package boundaries — no circular dependencies
- Shared tsconfig, eslint, and prettier configs in a `config/` package
- Only rebuild/test what changed (affected graph)
- Enforce package APIs — consumers use public exports only

---

### Q4: Design a real-time collaborative editor (like Google Docs)

**Example Answer:**

"The hardest problem here is conflict resolution when two users edit simultaneously. I'd use CRDTs (Conflict-free Replicated Data Types) — specifically a library like Yjs — which handles concurrent edits without a central lock. The frontend maintains a local copy of the document and syncs over WebSockets. Operations are applied locally immediately (optimistic) and broadcast to other peers. The server acts as a relay and persistence layer but doesn't arbitrate conflicts — the CRDT algorithm handles that. For presence (cursors, selections), I'd use an awareness protocol layered on top of Yjs."

**Key Bullets:**
- CRDTs (Yjs, Automerge) for conflict-free concurrent editing
- Optimistic local updates, broadcast to peers via WebSocket
- Awareness protocol for cursor positions and user presence
- Server is a relay + persistence layer, not a conflict arbiter
- Undo/redo requires per-user history, not a global stack
- Offline support: buffer operations locally, sync on reconnect

---

### Q5: How would you build a design system used across multiple teams?

**Example Answer:**

"A design system is a product, not a project — it needs dedicated ownership. I'd set up a separate repo (or monorepo package) with versioned component releases. Components are built framework-agnostic where possible, or at minimum documented for specific frameworks. Storybook is the source of truth for component states. The team publishes a changelog and follows semver strictly. I'd establish a contribution model — teams can propose components, but the design system team reviews for consistency. Tokens (colors, spacing, typography) are defined in a platform-agnostic format (Style Dictionary) so they can be consumed by web, iOS, and Android."

**Key Bullets:**
- Treat it as a product with dedicated ownership and roadmap
- Storybook for documentation and visual regression testing
- Semantic versioning with clear breaking change communication
- Design tokens via Style Dictionary for cross-platform consistency
- Contribution model: open PRs, design system team is gatekeeper
- Accessibility (WCAG AA) built into every component by default
- Visual regression tests (Chromatic) to catch unintended changes

---

## State Management

### Q6: How do you decide between local state, global state, and server state?

**Example Answer:**

"I use the simplest state that satisfies the need. If state is only needed within a component tree, it stays local with `useState` or `useReducer`. If it needs to be shared across distant parts of the app but is purely UI state (e.g., modal open, selected tab), I lift it to Context. If it comes from an API, it's server state — that belongs in React Query or SWR, not Redux. Global client-side state (e.g., authenticated user, cart) goes in Zustand or Redux if complex. The mistake I see most often is storing server data in Redux, which creates a duplicate source of truth."

**Key Bullets:**
- Local state: `useState`/`useReducer` for component-scoped data
- Shared UI state: Context or Zustand (lightweight, no boilerplate)
- Server state: React Query or SWR — handles caching, loading, stale/revalidate
- Global app state: Redux (complex) or Zustand (simple)
- Avoid duplicating server data in Redux — React Query is sufficient
- Ask: "does this state need to survive navigation?" to decide global vs. local

---

### Q7: When would you choose Redux vs. Zustand vs. React Query vs. Context?

**Example Answer:**

"React Query is my default for anything fetched from an API — it handles loading, error, caching, and background refetch out of the box. For global client state, Zustand is my default — it's minimal, no provider boilerplate, and scales well. Redux is justified when you need time-travel debugging, complex middleware, or are in a large existing Redux codebase. Context is fine for low-frequency updates (theme, locale, auth user) but causes performance issues if updated frequently because all consumers re-render."

**Key Bullets:**
- React Query: remote/server state, caching, background sync
- Zustand: simple global client state, minimal boilerplate
- Redux: complex state logic, middleware, large teams with existing Redux
- Context: low-update-frequency globals (theme, locale, auth)
- Never use Context for high-frequency state (perf issue)
- Combine tools: React Query + Zustand covers most apps without Redux

---

### Q8: How do you handle state synchronization across tabs/windows?

**Example Answer:**

"The simplest approach is the `BroadcastChannel` API, which lets tabs on the same origin send messages to each other. For example, if a user logs out in one tab, I broadcast a logout event and all other tabs respond by clearing auth state and redirecting. For more complex sync I'd use `localStorage` events — writing to localStorage fires a `storage` event in other tabs. For critical state like auth tokens I'd combine this with short-lived tokens and re-validation on tab focus. Service workers can also intercept and coordinate state across tabs."

**Key Bullets:**
- `BroadcastChannel` API for direct tab-to-tab messaging
- `localStorage` + `storage` event for cross-tab state changes
- Common use cases: logout, cart updates, theme changes
- Re-validate session on tab focus (`visibilitychange` event)
- Service workers for more complex coordination
- IndexedDB as a shared persistent store across tabs

---

## Performance Architecture

### Q9: How do you architect a site for Core Web Vitals (LCP, CLS, FID/INP)?

**Example Answer:**

"LCP is about getting the largest visible element rendered fast — I'd prioritize server-side rendering or static generation for above-the-fold content, preload the LCP image, and eliminate render-blocking resources. CLS is about layout stability — I always reserve space for images and ads with explicit width/height or aspect ratio CSS, and avoid injecting content above existing content. INP (Interaction to Next Paint) is about responsiveness — I defer non-critical JS, break up long tasks with `scheduler.yield()`, and avoid synchronous work on the main thread during interactions."

**Key Bullets:**
- **LCP**: SSR/SSG, `<link rel="preload">` for hero image, eliminate render-blocking CSS/JS
- **CLS**: explicit `width`/`height` on images, `aspect-ratio` CSS, no dynamic content injection above fold
- **INP**: defer non-critical JS, `scheduler.yield()` for long tasks, web workers for heavy computation
- Measure with Lighthouse, WebPageTest, and real user monitoring (RUM)
- Use `<link rel="preconnect">` for third-party origins
- Font loading: `font-display: swap` + preload to avoid invisible text

---

### Q10: When do you use SSR vs. SSG vs. CSR vs. ISR, and why?

**Example Answer:**

"SSG is my default when content doesn't change per-user and can be built at deploy time — it's the fastest option since it's just a CDN-served HTML file. ISR (Incremental Static Regeneration, a Next.js feature) extends SSG by revalidating pages on a schedule, which is great for content that changes infrequently like product pages. SSR is for pages that need per-request data — personalized dashboards, authenticated pages. CSR is for highly interactive tools where SEO doesn't matter and the user is already authenticated, like an admin panel or SaaS app."

**Key Bullets:**
- **SSG**: static content, best performance, deploy-time data (blogs, marketing)
- **ISR**: mostly static, periodically updated (product catalog, news)
- **SSR**: per-user or per-request data, SEO-important dynamic content
- **CSR**: authenticated apps, no SEO requirement, highly interactive
- Next.js App Router lets you mix strategies per component (React Server Components)
- Consider: SEO requirements, data freshness, personalization, and scale

---

### Q11: How would you architect code splitting and lazy loading at scale?

**Example Answer:**

"At the route level, every page is lazy loaded by default in frameworks like Next.js or React Router. Beyond that, I split by feature — if a feature is only used by 10% of users (e.g., an advanced settings panel), it should never be in the main bundle. I use dynamic `import()` with `React.lazy` and `Suspense` to load components on demand. At scale, I'd establish bundle budget rules in CI — a PR that pushes a bundle over a threshold fails the build. I'd also analyze bundles regularly with tools like `webpack-bundle-analyzer` or `vite-plugin-visualizer` to catch accidental large imports."

**Key Bullets:**
- Route-level splitting is baseline — most frameworks do this automatically
- Feature-level splitting with `React.lazy` + `Suspense` for conditional features
- Dynamic `import()` for large libraries loaded on interaction (e.g., a chart library)
- Bundle budgets enforced in CI (Bundlesize, Lighthouse CI)
- Regular bundle analysis with `webpack-bundle-analyzer` or `vite-plugin-visualizer`
- Prefetch next routes on hover/idle to hide loading latency

---

### Q12: How do you handle bundle size at scale across many teams?

**Example Answer:**

"The main risks at scale are duplicate dependencies (two teams bundling different versions of lodash), unreviewed large imports, and no one owning the overall budget. I'd address this by setting automated bundle size checks in CI that fail on regressions. I'd enforce shared dependency versions via the monorepo's root `package.json`. I'd publish a weekly bundle health report. I'd also audit `node_modules` for tree-shaking issues — libraries that don't support ESM can balloon bundle size. Education matters too: I'd run workshops on import cost and make tools like the Import Cost VSCode extension standard."

**Key Bullets:**
- Shared dependency versions in monorepo root to prevent duplication
- CI bundle size checks with regression alerts (Bundlesize, Lighthouse CI)
- ESM-only libraries in shared packages for tree-shaking
- Regular audits with `webpack-bundle-analyzer`
- Import Cost VSCode plugin for developer awareness
- Enforce no-barrel-file rules — `import { x } from 'lib'` not `import lib from 'lib'`

---

## Scalability & Team Patterns

### Q13: How do you architect a frontend so multiple teams can ship independently?

**Example Answer:**

"Independent shipping requires clear ownership boundaries and decoupled deployment. I'd define vertical slices by product domain — Team A owns /checkout, Team B owns /account — so they rarely touch each other's code. Each slice has its own routing, state, and API layer. Shared code lives in versioned packages so teams can upgrade on their own schedule. Feature flags decouple deployment from release — teams merge to main and flag-off until ready. CI/CD pipelines are per-team or at minimum have clear ownership so a broken test in one team doesn't block another."

**Key Bullets:**
- Vertical ownership by product domain (route-based or feature-based)
- Shared code in versioned packages, not copy-pasted
- Feature flags to decouple deploy from release
- Independent CI/CD pipelines per team or domain
- API contracts (TypeScript types, OpenAPI) to decouple from backend teams
- Clear ownership in CODEOWNERS to prevent accidental coupling

---

### Q14: How do you enforce consistency across teams (API contracts, component APIs)?

**Example Answer:**

"Consistency requires tools that make the right thing easy and the wrong thing hard. For component APIs I'd use TypeScript strictly — no `any`, well-typed props with JSDoc. The design system is the enforced source for UI — teams don't build their own buttons. For API contracts I'd use OpenAPI schemas and auto-generate TypeScript types so frontend and backend are always in sync. ESLint rules enforce patterns — no direct API calls outside of a service layer, no inline styles. ADRs (Architecture Decision Records) document why decisions were made so teams don't re-litigate the same debates."

**Key Bullets:**
- TypeScript strict mode across all packages
- Design system as the single source of UI truth
- OpenAPI + codegen for type-safe API contracts
- ESLint custom rules for architectural patterns (e.g., no direct fetch in components)
- ADRs for documenting and communicating architectural decisions
- Regular cross-team design reviews for new shared patterns

---

### Q15: How do you handle feature flags at the frontend layer?

**Example Answer:**

"I'd use a feature flag service like LaunchDarkly or a home-built solution backed by a simple API. Flags are fetched at app init and stored in a context provider. Components check flags via a `useFeatureFlag` hook. The key discipline is treating flags as temporary — every flag has a cleanup ticket created at the same time it's added. Flags should be boolean or simple variants, not complex config objects. For A/B tests, the flag service handles bucketing server-side so the user's bucket is consistent across sessions. Old flags that are 100% rolled out get cleaned up within a sprint."

**Key Bullets:**
- Feature flag service (LaunchDarkly, Unleash, or custom)
- `useFeatureFlag` hook for clean component-level checks
- Flags fetched at init, stored in Context or global state
- Every flag gets a cleanup ticket on creation — flags are temporary
- Server-side bucketing for A/B tests to ensure consistency
- Avoid flag logic deep in utility functions — keep it at the component/page boundary

---

### Q16: How do you design a frontend for A/B testing at scale?

**Example Answer:**

"A/B testing at scale requires that bucketing (which variant a user sees) happens server-side or at the edge — never in client JS — to avoid flicker and ensure consistency. The server sends the assigned variant with the initial page response, either as a cookie or in the HTML. The frontend reads the variant and renders accordingly, wrapped in a feature flag or experiment context. Analytics events include the variant ID so results can be attributed correctly. The experiment framework should make it trivial to add and remove experiments — if it's hard, engineers won't clean them up and you end up with permanent spaghetti."

**Key Bullets:**
- Server-side or edge bucketing to prevent flicker and ensure session consistency
- Variant delivered via cookie or SSR props, not determined client-side
- `useExperiment` hook or Experiment component for clean variant rendering
- All analytics events include experiment ID and variant
- Experiment registry to track active/archived experiments
- Cleanup is mandatory — experiments are removed after decision is made

---

## Reliability & Resilience

### Q17: How do you handle partial API failures gracefully?

**Example Answer:**

"The key principle is that a failure in one part of the page shouldn't destroy the whole experience. I'd design the UI in independent data zones — the feed loads independently from the sidebar, which loads independently from the header. Each zone handles its own error and loading state. React Query helps here because each query fails independently. For critical flows like checkout, I'd add retry logic with exponential backoff. For non-critical data (recommendations, ads), I'd show a fallback or nothing rather than an error. I'd also distinguish between transient failures (retry) and permanent failures (show error)."

**Key Bullets:**
- Independent data zones — partial failure doesn't cascade
- React Query's per-query error/loading state isolation
- Retry with exponential backoff for transient errors
- Graceful degradation: show stale data or fallback, not a crash
- Circuit breaker pattern for repeated failures (stop retrying after N attempts)
- User-facing error messages should suggest an action (retry, contact support)

---

### Q18: How would you architect error boundaries and fallback UI?

**Example Answer:**

"React Error Boundaries catch rendering errors and prevent the whole tree from unmounting. I'd place them at route level as a minimum — each page gets its own boundary so an error on one page doesn't affect navigation. For high-value widgets I'd add finer-grained boundaries. Every boundary has a fallback UI appropriate to its context — a full-page error for route-level, an inline error state for a widget. Errors are reported to an observability service (Sentry) from the `componentDidCatch` lifecycle. I'd also distinguish between recoverable errors (show retry button) and unrecoverable ones (redirect to error page)."

**Key Bullets:**
- Error Boundaries at route level as a minimum
- Finer-grained boundaries around high-value, isolated widgets
- Fallback UI proportional to scope (full-page vs. inline)
- Report to Sentry or similar in `componentDidCatch`
- Distinguish recoverable (retry) from unrecoverable (redirect/reload)
- Use `react-error-boundary` library for cleaner hook-based API

---

### Q19: How do you approach frontend observability (logging, tracing, alerting)?

**Example Answer:**

"Frontend observability has three layers: errors, performance, and user behavior. For errors I'd use Sentry — it captures JS exceptions, source maps for stack traces, and can alert on error rate spikes. For performance I'd use Real User Monitoring (RUM) — tools like Datadog RUM or web-vitals + custom reporting to track Core Web Vitals in production across real users, not just lab conditions. For user behavior I'd use structured analytics events that follow a consistent schema (object-action: `cart_item_added`). Alerting is based on error rate thresholds, not just raw counts, to account for traffic variance."

**Key Bullets:**
- Error tracking: Sentry with source maps for readable stack traces
- Performance: RUM for real-world Core Web Vitals (not just Lighthouse)
- Analytics: structured event schema (object-action naming), consistent properties
- Alert on error rate (%) not raw count — accounts for traffic spikes
- Distributed tracing: correlate frontend errors with backend trace IDs
- Session replay (LogRocket, Sentry) for debugging hard-to-reproduce issues

---

## Security

### Q20: How do you prevent XSS, CSRF, and clickjacking in a large app?

**Example Answer:**

"XSS is mostly prevented by never setting `innerHTML` with user content — React's JSX escapes by default, which is a big win. For cases where you need raw HTML (rich text editors), use a sanitizer like DOMPurify. CSRF is prevented with same-site cookies (`SameSite=Strict` or `Lax`) which is the modern standard — token-based CSRF headers are a fallback for older browsers. Clickjacking is prevented by the `X-Frame-Options: DENY` or `Content-Security-Policy: frame-ancestors 'none'` response header. A Content Security Policy is the overall defense layer — it specifies which origins can run scripts, blocking injected scripts even if XSS occurs."

**Key Bullets:**
- XSS: avoid `dangerouslySetInnerHTML`, sanitize with DOMPurify where needed
- CSP header to restrict script sources — blocks injected scripts
- CSRF: `SameSite=Strict/Lax` cookies, CSRF tokens as fallback
- Clickjacking: `X-Frame-Options: DENY` or CSP `frame-ancestors`
- Sanitize URL params before use — `javascript:` URLs are an XSS vector
- `Subresource Integrity (SRI)` for third-party scripts

---

### Q21: How do you architect authentication/authorization on the frontend?

**Example Answer:**

"Auth state lives server-side — the frontend is never the source of truth for whether a user is authenticated. I'd use HttpOnly cookies for session tokens so JS can't read them (XSS-resistant). On the frontend, I keep a lightweight auth context (user ID, roles, display name) populated from a `/me` endpoint on load. Route guards protect pages client-side for UX, but the real enforcement is server-side — the API rejects unauthorized requests regardless of what the frontend does. For OAuth flows I'd use the Authorization Code Flow with PKCE (not implicit flow). JWTs stored in localStorage are an XSS risk and should be avoided."

**Key Bullets:**
- HttpOnly cookies for tokens — not localStorage, not sessionStorage
- Auth context from `/me` endpoint — lightweight, no sensitive data
- Client-side route guards for UX only — server always enforces
- OAuth: Authorization Code + PKCE, never implicit flow
- Short-lived access tokens + refresh token rotation
- Role-based UI: hide unauthorized UI, but server still validates every request

---

### Q22: How do you handle sensitive data in client-side state?

**Example Answer:**

"The rule is: sensitive data should spend as little time on the client as possible and never be persisted. Tokens stay in HttpOnly cookies. PII like addresses or payment info should only be in component state during an active form interaction — not stored in Redux or localStorage. Payment data never touches your frontend state at all — use Stripe Elements or similar which keeps card data in an iframe owned by the payment provider. I'd audit the Redux/Zustand store in code review — if I see a credit card number or SSN as a state field, that's a blocker. Logging libraries should have PII scrubbers to avoid leaking sensitive data to analytics."

**Key Bullets:**
- Tokens in HttpOnly cookies only — never JS-accessible storage
- PII only in ephemeral component state during active use
- Payment data via iframe isolation (Stripe Elements, Braintree)
- Never log or track PII — scrub sensitive fields before analytics events
- Redux DevTools can expose state to browser extensions — consider disabling in prod
- Audit state shape in code review for accidental sensitive data storage

---

## Staff-Level Signals

### Q23: How do you approach architectural trade-offs?

**Example Answer:**

"I start by making the trade-offs explicit rather than jumping to a solution. Every architectural choice has a cost — complexity, performance, developer experience, operational burden. I try to name those costs clearly. For example, micro-frontends give teams deployment independence but add significant infra complexity and can harm user experience if not carefully managed. I also think about reversibility — prefer decisions that are easy to undo over ones that are hard to reverse. I document decisions in ADRs so the team understands why a choice was made and can revisit it with new information."

**Key Bullets:**
- Make trade-offs explicit — every decision has a cost
- Prefer reversible decisions when costs are similar
- Frame decisions around constraints: team size, timeline, scale, maintenance burden
- Document decisions in ADRs with context and alternatives considered
- Revisit decisions when constraints change — architecture should evolve
- Avoid cargo-culting patterns without understanding the problem they solve

---

### Q24: How do you evolve architecture without a full rewrite?

**Example Answer:**

"The strangler fig pattern is my default for incremental migration. You build the new architecture alongside the old one, route specific pages or features to the new system, and gradually migrate until the old system is strangled out. This means running both systems simultaneously for a period, which requires clear integration boundaries. For migrating state management from Redux to React Query + Zustand, I'd do it slice by slice — migrate one domain's data fetching at a time, leaving the rest in Redux. Feature flags help here by letting you switch traffic between old and new implementations without a deploy."

**Key Bullets:**
- Strangler fig pattern: build new alongside old, migrate incrementally
- Never stop shipping product to do a rewrite — migrate while delivering features
- Define clear integration boundaries between old and new systems
- Migrate domain by domain, not layer by layer
- Feature flags to switch between old/new implementations safely
- Establish measurable exit criteria — "done" means the old system is removed, not just unused
