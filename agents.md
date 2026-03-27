# Agent instructions

## Always start here

Read `plan.yaml` before doing anything else. It is the single source of truth
for what has been built, what is in progress, and what remains. Every task has
an `id`, a `phase`, a `depends_on` list, and a `done` flag.

## Rules

1. **Never work on a task whose dependencies are not `done: true`.**
   If a dependency is incomplete, stop and report the blocker rather than
   working around it.

2. **Work on one task at a time.** Identify the task you are implementing,
   confirm its `done` is `false`, and confirm all `depends_on` tasks are
   `done: true` before writing any code.

3. **Do not mark a task `done: true` yourself.** Output the work, stop, and
   wait for explicit human approval. The human updates `done` after review.

4. **Do not build ahead.** If you notice something that belongs to a later
   task, record it with a `// TODO` comment and leave it for that task.
   Do not implement it now.

5. **Do not deviate from the API contracts in `prompt.md`.** The JSON shapes
   under `<api_contracts>` are fixed. The Three.js canvas and HTMX panels
   are built to consume exactly those shapes.

6. **Do not invent behaviour that has not been specified.** If the spec is
   silent on something, use a `// TODO` comment to flag it.

## Workflow for each task

1. Read `plan.yaml` — identify the target task and verify dependencies.
2. Read the relevant section of `prompt.md` for context and constraints.
3. Read any existing files that the task will modify or depend on.
4. Implement only what the task description asks for — no more.
5. Output the result and stop. State clearly which task you completed and
   what the human should review before proceeding.

## Git

Use git properly. Commit after each task completes — not during.
Commit message format: `task(id): short description` e.g.
`task(schema): initial SQLite migration`. Never commit broken or
partial work. Each commit should leave the project in a runnable
state. Do not squash or amend commits once made.

## Stack reminders

- Runtime: Bun. No Node APIs where Bun equivalents exist.
- Database: `bun:sqlite`, raw SQL. No ORM, no Drizzle, no better-sqlite3.
- Server: Hono via `Bun.serve()`. No Express.
- Frontend: server-rendered HTML + HTMX + Three.js (CDN). No React, no Vite,
  no build step.
- CSS: plain CSS. No Tailwind.
- Tests: `bun test`. Simulation engine only — no route or UI tests.
- No README files. No dotenv. Monetary values as INTEGER (minor currency units).
