# ARGI Compatibility Baseline Design

## Context

ARGI `main` currently identifies itself as version `2.1.0-dev`, but its documented
compatibility commands and CI jobs no longer enforce compatibility. The rename from
Agentic Spring AI to ARGI intentionally changed Maven coordinates, Java packages,
configuration prefixes, module names, and framework class names. That rename is
the migration boundary; this design does not add compatibility shims for the
former coordinates.

## Goal

Establish the ARGI rename commit as the immutable public compatibility baseline
and restore executable binary, source, and Core-to-Extensions compatibility
gates for all future ARGI 2.x changes.

## Compatibility Contract

- The Core baseline commit is
  `e3de87198da2509168a975c461885cc6c4c1e7c7` (`refactor: rename project to ARGI
  (#108)`).
- Compatibility protection begins at that commit and covers ARGI Maven coordinates,
  Java packages, public and protected Java APIs, configuration keys, serialized
  formats, and documented runtime behavior.
- The former `io.github.agentic-spring-ai:*`, `io.github.agentic.spring.ai.*`, and
  `spring.ai.alibaba.*` contracts are outside this baseline. Users of those contracts
  follow the ARGI migration documentation.
- Public API removals after the ARGI baseline are not exempted from japicmp. The
  existing exclusions for migrated graph nodes are removed because those types were
  already absent at the ARGI baseline.
- Deprecation and removal rules in `docs/compatibility-policy.md` apply from the
  ARGI baseline forward.

## Core Compatibility Gate

`make compatibility-check` executes both compatibility scripts instead of
returning a successful skip message.

The binary gate:

1. Creates a detached worktree at the fixed ARGI baseline.
2. Builds the baseline and candidate artifacts in an isolated Maven repository.
3. Runs japicmp for `argi-graph-core`, `argi-agent-framework`, `argi-studio`,
   `argi-starter-graph-observation`, and `argi-starter-builtin-nodes`.
4. Fails on any public or protected binary incompatibility.
5. Produces Markdown reports under `target/binary-compatibility/`.

The source gate:

1. Installs the candidate ARGI artifacts into the isolated Maven repository.
2. Compiles `tools/compatibility/legacy-api-consumer` against the candidate.
3. Keeps the fixture on ARGI coordinates and packages so it represents the new
   baseline, not the pre-ARGI project.

## Extensions Compatibility Gate

- The Extensions baseline is the immutable commit
  `ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40` from
  `agentic-ai-java/argi-extensions`.
- CI checks out that commit under `.ci/argi-extensions`; it never follows a moving
  branch.
- The verifier creates an isolated Maven repository, runs Core `clean install`,
  and then runs the Extensions reactor tests against those exact candidate Core
  artifacts.
- A Core change that prevents Extensions from compiling or passing its default test
  suite fails the gate.
- Core does not add a production or build-time dependency on Extensions.

## CI Integration

The Build and Test workflow contains two independent jobs:

- `api-compatibility`: full-history checkout, dependency setup, and
  `make compatibility-check`.
- `extensions-compatibility`: Core checkout, pinned Extensions checkout, and the
  isolated verifier script.

The aggregate `build` job depends on both jobs in addition to formatting, Checkstyle,
tests, and the JDK matrix. A skipped compatibility command is not considered success.

## Wiring Regression Check

A deterministic shell check verifies that:

- the Make targets invoke the binary and source scripts;
- the binary script uses the fixed ARGI baseline;
- no public-type exclusion list remains;
- both workflow jobs exist and the aggregate build depends on them;
- the Extensions checkout uses the fixed commit;
- the policy describes the ARGI migration boundary and matches the executable gates.

This check runs before the expensive Maven compatibility builds so wiring regressions
fail quickly.

## Failure Semantics

- Missing baseline commits, artifacts, scripts, fixture files, or Extensions checkouts
  fail with a direct diagnostic and non-zero exit code.
- Maven and japicmp failures remain visible; scripts do not convert them into
  warnings or successful skips.
- Network retries may cover transient dependency downloads, but retries do not
  suppress a deterministic compile, test, or compatibility failure.

## Verification

The implementation is accepted only when all of the following pass from the isolated
worktree:

```bash
tools/scripts/verify-compatibility-wiring.sh
make compatibility-check
tools/scripts/verify-extensions-compatibility.sh .ci/argi-extensions
./mvnw -B test
make lint
make licenses-check
git diff --check
```

The GitHub Actions workflow must also parse successfully and expose both compatibility
jobs as dependencies of `build`.

## Non-Goals

- Reintroducing old Agentic Spring AI coordinates, packages, or configuration aliases.
- Fixing runtime defects identified in the repository audit.
- Changing public runtime behavior or adding new production dependencies.
- Changing the Extensions source repository as part of this Core change.

## Rollback

The change is limited to policy, compatibility fixtures/scripts, Make wiring,
and CI. Rollback removes the two jobs and restores the previous scripts; it does
not require a runtime or data migration. A rollback also removes the claimed
compatibility guarantee, so policy and executable gates must always change
together.
