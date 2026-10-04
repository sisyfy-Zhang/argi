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
	if [[ ! -f "${REPO_ROOT}/$1" ]]; then
		failures+=("missing file: $1")
	fi
}

require_literal() {
	[[ -f "${REPO_ROOT}/$1" ]] || return 0
	if ! grep -Fq -- "$2" "${REPO_ROOT}/$1"; then
		failures+=("$1 must contain: $2")
	fi
}

reject_literal() {
	[[ -f "${REPO_ROOT}/$1" ]] || return 0
	if grep -Fq -- "$2" "${REPO_ROOT}/$1"; then
		failures+=("$1 must not contain: $2")
	fi
}

for gate in binary source; do
	script="tools/scripts/verify-core-${gate}-compatibility.sh"
	require_file "${script}"
	commands="$(make -s -n -C "${REPO_ROOT}" "${gate}-compatibility-check")"
	if ! grep -Fxq -- "${script}" <<< "${commands}"; then
		failures+=("${gate}-compatibility-check does not execute ${script}")
	fi
done
require_file "tools/compatibility/legacy-api-consumer/pom.xml"
require_literal "tools/compatibility/legacy-api-consumer/pom.xml" \
	'<groupId>io.github.agentic-ai</groupId>'
require_literal "tools/scripts/verify-core-binary-compatibility.sh" \
	'BASE_COMMIT="${1:-e3de87198da2509168a975c461885cc6c4c1e7c7}"'
reject_literal "tools/scripts/verify-core-binary-compatibility.sh" 'REMOVED_BUILTIN'
reject_literal "tools/scripts/verify-core-binary-compatibility.sh" '--exclude'
require_file 'tools/scripts/verify-extensions-compatibility.sh'
require_literal 'tools/scripts/verify-extensions-compatibility.sh' 'clean install'
require_literal 'tools/scripts/verify-extensions-compatibility.sh' 'clean test'
require_file '.github/workflows/build-and-test.yml'
require_file 'docs/compatibility-policy.md'
require_literal '.github/workflows/build-and-test.yml' '  api-compatibility:'
require_literal '.github/workflows/build-and-test.yml' '  extensions-compatibility:'
require_literal '.github/workflows/build-and-test.yml' \
	'ref: ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40'
require_literal '.github/workflows/build-and-test.yml' \
	'needs: [format, check-style, test, jdk-compatibility, api-compatibility, extensions-compatibility]'
require_literal 'docs/compatibility-policy.md' 'e3de87198da2509168a975c461885cc6c4c1e7c7'
require_literal 'docs/compatibility-policy.md' 'ec023a24910a0a30c0e3e1c810e4c3ac2ef0dc40'

if (( ${#failures[@]} > 0 )); then
	printf 'Compatibility wiring verification failed:\n' >&2
	printf -- '- %s\n' "${failures[@]}" >&2
	exit 1
fi
printf 'Compatibility wiring verification passed.\n'
