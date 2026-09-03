# wayworks and Nemo — where the line falls

**Status:** proposed · **Written:** 2026-09-03 · Companion to
`ristretto-ai/docs/nemo-architecture.md`.

Ristretto is now Nemo, a personal assistant that can write code. That
re-framing changes what wayworks is responsible for, and it turns out wayworks
is holding less than it should while Nemo is holding more.

## The division

**wayworks — what to do, and how to do it well.** The dev loop, the deploy
loop, the craft skills, and the conventions a repository adopts:
`.cc-dev.yaml`, `.cc-verify`, `.cc-deploy.yaml`. This is what you reach for in
a session when you are at the machine.

**Nemo — making it happen when nobody is watching.** Dispatch, routing a
different model to each stage, supervising a run for an hour, artifacts,
events, memory, and the surfaces.

Nemo is not a UI over wayworks. A skill is markdown that instructs an agent
somebody already started; something has to start that agent at three in the
afternoon when nobody is home. But wayworks should own more of the craft than
it currently does.

## What should move here

### The stage definitions

Nemo's `runner.py` contains a `role_prompt` function holding the actual
instructions for what a plan stage does, what a review stage looks for, what
repair means. That is craft living in the orchestrator: improving how review
works currently means editing Nemo.

Worse, **the same loop exists twice**. `/loop-dev` is the interactive
implementation here; Nemo's multi-stage tiers are a second one there. Same
craft, written twice, free to drift with nothing to notice.

The test worth applying: *could one definition serve both the interactive and
the autonomous path?* Today it cannot. It should.

Shape, not yet designed: wayworks declares the stages and what each is for;
Nemo decides which model runs each and supervises the result. The relationship
already exists for `.cc-verify` — wayworks defines it, Nemo only reads it.

### Deploy configuration

`loop-deploy` is written and has a gate hook, and it has **never run once**.
Not one of six repositories has a `.cc-deploy.yaml`, and the command correctly
refuses to guess deploy commands.

The first useful step is not code. It is writing one `.cc-deploy.yaml` for a
real project and running `/loop-deploy` by hand, to find out whether the loop
works before anything is built on top of it.

`harness-init` should scaffold a `.cc-deploy.yaml` alongside the dev-loop
files — as a commented template that refuses to run until filled in, never a
guess.

### The vault pointer

Nemo will inject a project's long-term note into its stages so a run starts
from what previous runs learned. Which note belongs to which repository is a
per-repository fact — exactly the shape of `.cc-verify` — so it belongs in
`.cc-dev.yaml` and should be scaffolded by `harness-init`.

## The seam has no contract test

Nemo depends on these conventions by reading files from disk:
`.cc-verify` (its preflight and verify stage), `.cc-dev.yaml`, and soon
`.cc-deploy.yaml`.

If any of them is renamed or restructured here, Nemo's preflight and verify
break — and **nothing in either repository would catch it**, because they are
separate repos with separate suites. This is the only real coupling between
the two projects and it is currently undefended.

Worth fixing cheaply: a test on this side asserting the filenames and required
keys, so a change that breaks Nemo fails here first and deliberately.

## What does not change

The craft skills — architect, security, qa, frontend-dev, pm and the rest —
are untouched by any of this. They are used in sessions by a person, which is
what they were built for. Nothing above suggests moving them.
