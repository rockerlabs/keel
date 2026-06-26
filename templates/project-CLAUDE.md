# <Project name>

> Per-project always-loaded context. Keep it ≤ ~8–10K tokens; move detail to the on-demand tier once it
> outgrows that (see `FRAMEWORK.md` → "Project context-file structure").

## Where things live (map)

- **This file** — how the project works + the roadmap index (startup tier).
- **`<on-demand file>`** — full changelog, closed-work index, detailed plans (pointer, not loaded).
- **memory** — reusable invariants (recalled pointwise).

`project-id: <stable-id>`  <!-- logical project id; default = this project's registry name -->

## Overview

<what this project is, in two or three lines>

## Stack & conventions

<language, framework, build/test commands, the lint gate, any project-specific constraints>

## Roadmap / backlog

<open work — inline here while small; a pointer to an on-demand backlog once it grows>

## Recently closed (cooldown buffer)

<the last ≤2 closed tasks; sweep to the changelog/git log after a milestone or two>

## Changelog

| Date | What changed — one line |
|------|-------------------------|
