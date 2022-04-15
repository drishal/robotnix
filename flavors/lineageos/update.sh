#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

branch=$1

args=(
    --cache-search-path ../../
    --ref-type branch
    "https://github.com/ForkLineageOS/android"
    "$branch"
)

export TMPDIR=/tmp

../../scripts/mk_repo_file.py --out "${branch}/repo.json" "${args[@]}"

echo Updated branch "$branch". End epoch: "$(date +%s)"
