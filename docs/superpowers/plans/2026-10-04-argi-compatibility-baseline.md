# ARGI Compatibility Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore executable Core API and Core-to-Extensions compatibility
gates using the ARGI rename as the immutable 2.x baseline.

**Architecture:** A fast shell wiring check protects the Make, script, policy,
and workflow contracts. The expensive gates build an immutable Core baseline,
compare five candidate artifacts with japicmp, compile an ARGI source fixture,
and test a pinned Extensions checkout in an isolated Maven repository.

**Tech Stack:** Bash, GNU Make, Maven Wrapper, japicmp, GitHub Actions YAML,
Java 17.

**Spec:**
`docs/superpowers/specs/2026-10-04-argi-compatibility-baseline-design.md`

## Global Constraints

- Core baseline:
  `e3de87198da2509168a975c461885cc6c4c1e7c7`.
- Extensions baseline:
  `ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40`.
- Protect only ARGI coordinates and packages; do not add old-coordinate shims.
- Keep Java 17 and Maven 3.9.1 compatibility.
- Add no production dependencies.
- Do not exempt public ARGI types from japicmp.
- Keep Core independently buildable without Extensions.
- Use Apache 2.0 headers and signed-off commits.

## Execution Record

Execution mode: inline, in the isolated `codex/argi-compatibility-baseline`
worktree. Runtime Java code and production dependencies remain unchanged.

- Tasks 1-4 implementation and focused verification: complete.
- Task 5 acceptance verification: complete. Implementation changes are
  consolidated into one signed-off commit rather than four intermediate
  commits; the branch and worktree are kept local, without push or PR.

Plan adjustments made during implementation:

- Commit Tasks 1-4 atomically after acceptance verification. The final wiring
  checker references all four tasks, so intermediate commits would contain a
  gate that fails solely because later files are absent.
- Run binary and source gates sequentially through recursive Make, even under
  `make -j`, because they share candidate output directories and Maven state.
- Clean only candidate runtime modules before the binary build to prevent
  stale classes from hiding API removals. Cleaning the parent would remove
  the isolated Maven repository under `target/binary-compatibility/`.
- Use one fresh pinned Extensions checkout and one fresh Maven repository for
  the complete Extensions acceptance run. Its Core `clean install` includes
  the default full Core test suite, avoiding redundant reactor runs.

Acceptance evidence:

- All four wiring changes were observed failing before their corresponding
  implementation, then passing afterwards.
- `make compatibility-check`: five japicmp artifact comparisons and the ARGI
  source consumer passed (`/tmp/argi-full-compatibility.log`).
- Negative API probe: removing `NodeOutput.class` from a temporary copy of the
  candidate graph JAR caused japicmp to exit 1 with `CLASS_REMOVED`, using the
  gate's flags. No tracked source or candidate artifact was changed.
- Invalid Extensions checkout: verifier exited 2 before starting Maven.
- Missing-file regression probe in an isolated archived repository: before
  the final correction, deleting the policy and workflow incorrectly passed
  wiring verification. Explicit existence assertions now make the probe exit
  1 with both missing paths; restoring both files makes it pass again.
- Core isolated `clean install`: all seven reactor modules passed, with 1278
  tests reported, 0 failures, 0 errors, and 219 skips from existing test
  configuration (`/tmp/argi-extensions-compatibility.log`).
- Pinned Extensions `clean test`: all 73 reactor modules passed, with 399
  tests reported, 0 failures, 0 errors, and 27 skips. The existing
  `rag/argi-rag/pom.xml` separately sets `skipTests=true`; its integration
  tests were compiled but not run. Default test configuration was preserved,
  so passing this gate does not prove those excluded scenarios.
- Verification ran with JDK 17.0.3 and Maven Wrapper 3.9.16. The verifier
  removed its fresh temporary Maven repository on successful exit.
- `make lint`, `make licenses-check`, `make yaml-lint`, policy Markdown lint,
  Bash syntax checks, structured workflow validation, and `git diff --check`
  passed. License scan found 0 invalid files across 1297 files.

---

### Task 1: Restore Make and source-compatibility wiring

**Files:**

- Create: `tools/scripts/verify-compatibility-wiring.sh`
- Modify: `tools/make/java.mk:48-59`
- Test: `tools/scripts/verify-compatibility-wiring.sh`

**Interfaces:**

- Consumes: existing binary/source scripts and ARGI source fixture.
- Produces: `make compatibility-wiring-check` and an executable
  `make compatibility-check` entry point used by CI and later tasks.

- [x] **Step 1: Write the failing wiring check**

Create `tools/scripts/verify-compatibility-wiring.sh` with this initial content:

```bash
#!/usr/bin/env bash
#
# Copyright 2024-2026 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -euo pipefail

readonly REPO_ROOT="$(git rev-parse --show-toplevel)"
declare -a failures=()

require_file() {
  local relative_path="$1"
  if [[ ! -f "${REPO_ROOT}/${relative_path}" ]]; then
    failures+=("missing file: ${relative_path}")
  fi
}

require_literal() {
  local relative_path="$1"
  local literal="$2"
  if ! grep -Fq -- "${literal}" "${REPO_ROOT}/${relative_path}"; then
    failures+=("${relative_path} must contain: ${literal}")
  fi
}

reject_literal() {
  local relative_path="$1"
  local literal="$2"
  if grep -Fq -- "${literal}" "${REPO_ROOT}/${relative_path}"; then
    failures+=("${relative_path} must not contain: ${literal}")
  fi
}

require_file "tools/scripts/verify-core-binary-compatibility.sh"
require_file "tools/scripts/verify-core-source-compatibility.sh"
require_file "tools/compatibility/legacy-api-consumer/pom.xml"
require_literal "tools/make/java.mk" \
  "tools/scripts/verify-core-binary-compatibility.sh"
require_literal "tools/make/java.mk" \
  "tools/scripts/verify-core-source-compatibility.sh"
reject_literal "tools/make/java.mk" \
  "Legacy binary compatibility check skipped"
reject_literal "tools/make/java.mk" \
  "Legacy source compatibility check skipped"
require_literal "tools/compatibility/legacy-api-consumer/pom.xml" \
  "<groupId>io.github.agentic-ai</groupId>"
require_literal "tools/compatibility/legacy-api-consumer/pom.xml" \
  "<artifactId>argi-agent-framework</artifactId>"

if (( ${#failures[@]} > 0 )); then
  printf 'Compatibility wiring verification failed:\n' >&2
  printf -- '- %s\n' "${failures[@]}" >&2
  exit 1
fi

printf 'Compatibility wiring verification passed.\n'
```

Make the file executable:

```bash
chmod +x tools/scripts/verify-compatibility-wiring.sh
```

- [x] **Step 2: Run the check and verify RED**

Run:

```bash
tools/scripts/verify-compatibility-wiring.sh
```

Expected: exit `1`, reporting that `tools/make/java.mk` does not invoke the
binary and source scripts and still contains both skip messages.

- [x] **Step 3: Restore the Make targets**

Replace the compatibility section in `tools/make/java.mk` with:

<!-- markdownlint-disable MD010 MD013 -->

```make
.PHONY: compatibility-wiring-check
compatibility-wiring-check:
	@$(LOG_TARGET)
	tools/scripts/verify-compatibility-wiring.sh

.PHONY: binary-compatibility-check
binary-compatibility-check: ## Compare public and protected APIs against the ARGI baseline
	@$(LOG_TARGET)
	tools/scripts/verify-core-binary-compatibility.sh

.PHONY: source-compatibility-check
source-compatibility-check:
	@$(LOG_TARGET)
	tools/scripts/verify-core-source-compatibility.sh

.PHONY: compatibility-check
compatibility-check: compatibility-wiring-check binary-compatibility-check source-compatibility-check
```

<!-- markdownlint-enable MD010 MD013 -->

- [x] **Step 4: Run the focused GREEN checks**

Run:

```bash
tools/scripts/verify-compatibility-wiring.sh
make compatibility-wiring-check
make source-compatibility-check
```

Expected: all commands exit `0`; the source fixture compiles against candidate
ARGI artifacts.

- [x] **Step 5: Commit the wiring restoration (consolidated atomic commit)**

```bash
git add tools/make/java.mk \
  tools/scripts/verify-compatibility-wiring.sh
git commit -s -m "ci: restore ARGI compatibility commands"
```

### Task 2: Establish the binary ARGI baseline without API exemptions

**Files:**

- Modify: `tools/scripts/verify-compatibility-wiring.sh`
- Modify: `tools/scripts/verify-core-binary-compatibility.sh:20-137`
- Test: `tools/scripts/verify-compatibility-wiring.sh`

**Interfaces:**

- Consumes: Task 1 wiring and the fixed Core commit.
- Produces: a five-artifact japicmp gate with no public-type exclusions.

- [x] **Step 1: Extend the wiring check before changing the binary gate**

Insert these assertions before the final `if` block in
`tools/scripts/verify-compatibility-wiring.sh`:

```bash
require_literal "tools/scripts/verify-core-binary-compatibility.sh" \
  'BASE_COMMIT="${1:-e3de87198da2509168a975c461885cc6c4c1e7c7}"'
reject_literal "tools/scripts/verify-core-binary-compatibility.sh" \
  "REMOVED_BUILTIN"
reject_literal "tools/scripts/verify-core-binary-compatibility.sh" \
  "japicmp_args+=(--exclude"
```

- [x] **Step 2: Run the check and verify RED**

Run:

```bash
tools/scripts/verify-compatibility-wiring.sh
```

Expected: exit `1`, reporting the old baseline and public-type exclusions.

- [x] **Step 3: Change the binary baseline and remove exclusions**

In `tools/scripts/verify-core-binary-compatibility.sh`:

```bash
readonly BASE_COMMIT="${1:-e3de87198da2509168a975c461885cc6c4c1e7c7}"
```

Delete all `REMOVED_BUILTIN_*` constants. Change `compare_module()` to accept
only `label`, `baseline_jar`, and `candidate_jar`; remove the `excludes`
variable and the conditional `--exclude` argument. Invoke the built-in nodes
comparison with only the two JAR paths.

- [x] **Step 4: Run the binary gate and complete compatibility gate**

Run:

```bash
tools/scripts/verify-compatibility-wiring.sh
make binary-compatibility-check
make compatibility-check
```

Expected: exit `0`; five japicmp reports are generated under
`target/binary-compatibility/`, and the source fixture also compiles.

- [x] **Step 5: Commit the binary baseline (consolidated atomic commit)**

```bash
git add tools/scripts/verify-compatibility-wiring.sh \
  tools/scripts/verify-core-binary-compatibility.sh
git commit -s -m "ci: enforce the ARGI binary baseline"
```

### Task 3: Restore isolated Extensions compatibility verification

**Files:**

- Modify: `tools/scripts/verify-compatibility-wiring.sh`
- Create: `tools/scripts/verify-extensions-compatibility.sh`
- Test: `tools/scripts/verify-compatibility-wiring.sh`

**Interfaces:**

- Consumes: candidate Core reactor and an explicit Extensions checkout path.
- Produces: `verify-extensions-compatibility.sh <checkout>` with isolated Maven
  repository semantics.

- [x] **Step 1: Add failing verifier assertions**

Insert these assertions before the final `if` block in the wiring check:

```bash
require_file "tools/scripts/verify-extensions-compatibility.sh"
require_literal "tools/scripts/verify-extensions-compatibility.sh" \
  'clean install'
require_literal "tools/scripts/verify-extensions-compatibility.sh" \
  'clean test'
```

- [x] **Step 2: Run the check and verify RED**

Run:

```bash
tools/scripts/verify-compatibility-wiring.sh
```

Expected: exit `1` with `missing file:
tools/scripts/verify-extensions-compatibility.sh`.

- [x] **Step 3: Restore the verifier with an Apache header**

Create `tools/scripts/verify-extensions-compatibility.sh` with this execution
contract:

```bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core_dir="$(cd "${script_dir}/../.." && pwd)"
extensions_dir="${1:-}"

if [[ -z "${extensions_dir}" || ! -f "${extensions_dir}/pom.xml" ]]; then
  echo "Usage: $0 .ci/argi-extensions" >&2
  exit 2
fi

extensions_dir="$(cd "${extensions_dir}" && pwd)"
tmp_parent="${TMPDIR:-/tmp}"
temporary_repo="$(mktemp -d "${tmp_parent%/}/argi-maven-repo.XXXXXX")"
cleanup() {
  if [[ "${temporary_repo}" == "${tmp_parent%/}"/argi-maven-repo.* ]]; then
    rm -rf "${temporary_repo}"
  fi
}
trap cleanup EXIT

echo "Testing and installing Core into ${temporary_repo}"
"${core_dir}/mvnw" -B -f "${core_dir}/pom.xml" \
  -Dmaven.repo.local="${temporary_repo}" clean install

extensions_maven="${extensions_dir}/mvnw"
if [[ ! -x "${extensions_maven}" ]]; then
  extensions_maven="${MAVEN_CMD:-mvn}"
fi

echo "Testing Extensions from ${extensions_dir}"
"${extensions_maven}" -B -f "${extensions_dir}/pom.xml" \
  -Dmaven.repo.local="${temporary_repo}" clean test
```

Add the standard Apache 2.0 shell header above this block and make the file
executable.

- [x] **Step 4: Run syntax and isolated reactor verification**

```bash
bash -n tools/scripts/verify-extensions-compatibility.sh
tools/scripts/verify-compatibility-wiring.sh
tmp_parent="${TMPDIR:-/tmp}"
extensions_tmp="$(mktemp -d \
  "${tmp_parent%/}/argi-extensions-check.XXXXXX")"
cleanup_extensions_tmp() {
  case "${extensions_tmp}" in
    "${tmp_parent%/}"/argi-extensions-check.*) rm -rf "${extensions_tmp}" ;;
    *) echo "Refusing to remove unexpected path: ${extensions_tmp}" >&2 ;;
  esac
}
trap cleanup_extensions_tmp EXIT
git clone --filter=blob:none --no-checkout \
  https://github.com/agentic-ai-java/argi-extensions.git \
  "${extensions_tmp}/repo"
git -C "${extensions_tmp}/repo" fetch --depth=1 origin \
  ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40
git -C "${extensions_tmp}/repo" checkout --detach \
  ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40
tools/scripts/verify-extensions-compatibility.sh \
  "${extensions_tmp}/repo"
```

Expected: Bash syntax, wiring, Core reactor, and pinned Extensions reactor all
exit `0`; the trap removes only the validated temporary checkout.

- [x] **Step 5: Commit the Extensions verifier (consolidated atomic commit)**

```bash
git add tools/scripts/verify-compatibility-wiring.sh \
  tools/scripts/verify-extensions-compatibility.sh
git commit -s -m "ci: restore Extensions compatibility verification"
```

### Task 4: Restore CI jobs and align compatibility policy

**Files:**

- Modify: `tools/scripts/verify-compatibility-wiring.sh`
- Modify: `.github/workflows/build-and-test.yml:57-95`
- Modify: `docs/compatibility-policy.md:1-69`
- Test: `tools/scripts/verify-compatibility-wiring.sh`

**Interfaces:**

- Consumes: Tasks 1-3 commands and pinned SHAs.
- Produces: blocking `api-compatibility` and `extensions-compatibility` jobs.

- [x] **Step 1: Add failing workflow and policy assertions**

Insert these assertions before the final `if` block in the wiring check:

```bash
require_literal ".github/workflows/build-and-test.yml" \
  "api-compatibility:"
require_literal ".github/workflows/build-and-test.yml" \
  "extensions-compatibility:"
require_literal ".github/workflows/build-and-test.yml" \
  "ref: ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40"
require_literal ".github/workflows/build-and-test.yml" \
  "needs: [format, check-style, test, jdk-compatibility, api-compatibility, extensions-compatibility]"
require_literal "docs/compatibility-policy.md" \
  "e3de87198da2509168a975c461885cc6c4c1e7c7"
require_literal "docs/compatibility-policy.md" \
  "ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40"
```

- [x] **Step 2: Run the check and verify RED**

Run:

```bash
tools/scripts/verify-compatibility-wiring.sh
```

Expected: exit `1` listing both missing jobs, the missing build dependencies,
and both missing policy SHAs.

- [x] **Step 3: Add the API compatibility job**

Add after `jdk-compatibility` in `.github/workflows/build-and-test.yml`:

```yaml
  api-compatibility:
    if: (github.repository == 'agentic-ai-java/argi')
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          fetch-depth: 0
      - uses: ./tools/github-actions/setup-deps
      - run: make compatibility-check
```

- [x] **Step 4: Add the pinned Extensions compatibility job**

Add immediately after `api-compatibility`:

```yaml
  extensions-compatibility:
    if: (github.repository == 'agentic-ai-java/argi')
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: ./tools/github-actions/setup-deps
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          repository: agentic-ai-java/argi-extensions
          ref: ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40
          path: .ci/argi-extensions
      - run: tools/scripts/verify-extensions-compatibility.sh .ci/argi-extensions
```

Change the `build` dependency line to:

```yaml
    needs: [format, check-style, test, jdk-compatibility, api-compatibility, extensions-compatibility]
```

- [x] **Step 5: Align the policy with the executable contract**

Add a migration-boundary section near the top of
`docs/compatibility-policy.md`:

```markdown
## ARGI Baseline

The rename from Agentic Spring AI to ARGI is the migration boundary. ARGI 2.x
compatibility is measured from Core commit
`e3de87198da2509168a975c461885cc6c4c1e7c7`. Earlier Maven coordinates,
packages, and configuration prefixes require migration and are not part of this
baseline.

Core-to-Extensions compatibility is verified against the immutable Extensions
commit `ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40`.
```

Keep the existing protected-surface and deprecation rules unchanged; they apply
after this baseline.

- [x] **Step 6: Run workflow and policy GREEN checks**

```bash
tools/scripts/verify-compatibility-wiring.sh
make yaml-lint
git diff --check
```

Expected: all commands exit `0`.

- [x] **Step 7: Commit CI and policy wiring (consolidated atomic commit)**

```bash
git add .github/workflows/build-and-test.yml \
  docs/compatibility-policy.md \
  tools/scripts/verify-compatibility-wiring.sh
git commit -s -m "ci: gate ARGI against Core and Extensions baselines"
```

### Task 5: Run complete acceptance verification

**Files:**

- Verify only; no planned source changes.

**Interfaces:**

- Consumes: all commands and CI contracts from Tasks 1-4.
- Produces: completion evidence for the first remediation batch.

- [x] **Step 1: Verify tracked scope and signed commits**

```bash
git status --short
git log --format='%h %s%n%(trailers:key=Signed-off-by,valueonly)' \
  origin/main..HEAD
```

Expected: no unexpected tracked files and every implementation commit has a
`Signed-off-by` trailer.

- [x] **Step 2: Run local compatibility gates**

```bash
tools/scripts/verify-compatibility-wiring.sh
make compatibility-check
```

Expected: wiring, binary comparison, and source fixture all pass.

- [x] **Step 3: Run pinned Extensions acceptance verification**

Use a fresh pinned checkout and isolated repository for the acceptance run.
The execution record documents why the Task 3 and acceptance runs were
combined:

```bash
tmp_parent="${TMPDIR:-/tmp}"
extensions_tmp="$(mktemp -d \
  "${tmp_parent%/}/argi-extensions-final.XXXXXX")"
cleanup_extensions_tmp() {
  case "${extensions_tmp}" in
    "${tmp_parent%/}"/argi-extensions-final.*) rm -rf "${extensions_tmp}" ;;
    *) echo "Refusing to remove unexpected path: ${extensions_tmp}" >&2 ;;
  esac
}
trap cleanup_extensions_tmp EXIT
git clone --filter=blob:none --no-checkout \
  https://github.com/agentic-ai-java/argi-extensions.git \
  "${extensions_tmp}/repo"
git -C "${extensions_tmp}/repo" fetch --depth=1 origin \
  ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40
git -C "${extensions_tmp}/repo" checkout --detach \
  ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40
tools/scripts/verify-extensions-compatibility.sh \
  "${extensions_tmp}/repo"
```

Expected: Core and Extensions reactors pass from a clean isolated Maven
repository.

- [x] **Step 4: Run repository quality gates**

```bash
./mvnw -B test
make lint
make licenses-check
git diff --check origin/main...HEAD
```

Expected: all commands exit `0`.

- [x] **Step 5: Record the final state**

```bash
git status --short --branch
git log --oneline --decorate origin/main..HEAD
```

Expected: the branch is clean and contains the design, plan, and one signed-off
atomic implementation commit, as documented in the execution record.
