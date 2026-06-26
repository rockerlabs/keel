# Keel — positioning notes

Raw material for future posts, press release, README intro. Unpolished —
capture first, edit later.

---

## The problem

Every AI session starts from scratch. The AI remembers nothing:
not your project structure, not the decisions you already made, not the
conventions you follow, not why things are set up the way they are.

You spend the first 10–15 minutes re-explaining context. Multiply by
hundreds of sessions a year. And the AI still makes mistakes because it
missed something.

The opposite extreme doesn't work either: dump everything into the context
and the AI drowns in noise and starts hallucinating the wrong fact from the
wrong project.

---

## What Keel is

A system that answers one question: *what exactly to load into the AI's
context, when, and how much.*

Three ideas:

**1. Not everything needs to be loaded all the time.**
There's a minimal stable core that goes into every session — short, stable,
fast. Everything else is loaded on demand when it's relevant. This is
called tiering. It's why the system works even with small context windows
on local models — you're not trying to fit everything, you're choosing.

**2. What's worth preserving vs. what isn't.**
Most people carefully configure their tools and let knowledge evaporate.
Keel says the opposite: tools become outdated in a year; your decisions
and domain understanding don't. Preserve judgment. Keep mechanisms thin
and disposable.

**3. The system improves from real friction, not from wanting to be complete.**
No "add everything just in case" principle. Every element exists because
something went wrong without it. This protects it from growing into
bureaucracy.

---

## Concrete result

*Before:* open session → explain project → explain conventions → explain
why things are set up this way → AI makes a mistake anyway because it
missed something.

*After:* open session → AI already knows what it needs to know → start
working immediately.

---

## Why especially valuable for local models

Hosted models (Claude, GPT) have large context windows — you can throw a
lot in and hope for the best. Local models (Ollama, Llama, Mistral) have
4–32K tokens — no room. You can't load everything. Keel gives you an
architecture where you control exactly what's inside, and the model
performs well even with a small window.

---

## Positioning angles (to explore)

- "The missing layer under any AI workflow tool" — not a competitor to
  superpowers/Cursor/etc., but the infrastructure that makes them
  sustainable over months and years.
- "Knowledge OS for human-AI work" — the OS analogy: just like an OS
  manages what a program has access to, Keel manages what the AI has
  access to.
- "Works with local models" — explicit differentiator, most frameworks
  assume large context.
- "Compounds over time" — unlike prompt templates that reset every session,
  this accumulates.

---

## What Keel is NOT

- Not a prompt template library
- Not a workflow automation tool (that's superpowers, Cursor, etc.)
- Not specific to one AI provider or model
- Not a tool that requires a subscription or API key to function

---

## Notes from design discussions (2026-06-26)

- Name "Keel" chosen for the nautical analogy: the keel is the thin,
  hidden structural spine of a ship — everything else is built on it.
  Fits the "thin layers + foundation" philosophy.
- Target: private → public when content is ready. No rush on distribution
  until a real second user exists (P0 principle).
- Thin layers are a first-class design constraint, not an optimization —
  required for local model compatibility from day one.
