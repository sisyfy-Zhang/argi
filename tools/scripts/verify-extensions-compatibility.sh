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

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CORE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
extensions_dir="${1:-}"

if [[ -z "${extensions_dir}" || ! -f "${extensions_dir}/pom.xml" ]]; then
	echo "Usage: $0 .ci/argi-extensions" >&2
	exit 2
fi
extensions_dir="$(cd "${extensions_dir}" && pwd)"
readonly TMP_PARENT="${TMPDIR:-/tmp}"
readonly MAVEN_REPO="$(mktemp -d "${TMP_PARENT%/}/argi-maven-repo.XXXXXX")"

cleanup() {
	if [[ "${MAVEN_REPO}" == "${TMP_PARENT%/}"/argi-maven-repo.* && -d "${MAVEN_REPO}" ]]; then
		rm -rf "${MAVEN_REPO}"
	fi
}
trap cleanup EXIT

echo "Testing and installing Core into ${MAVEN_REPO}"
cd "${CORE_DIR}"
./mvnw -B -Dmaven.repo.local="${MAVEN_REPO}" clean install

extensions_maven="${extensions_dir}/mvnw"
if [[ ! -x "${extensions_maven}" ]]; then
	extensions_maven="${MAVEN_CMD:-mvn}"
fi
echo "Testing Extensions from ${extensions_dir} against candidate Core artifacts"
cd "${extensions_dir}"
"${extensions_maven}" -B -f pom.xml -Dmaven.repo.local="${MAVEN_REPO}" clean test
