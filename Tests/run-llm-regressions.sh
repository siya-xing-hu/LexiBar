#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/lexibar-llm-tests.XXXXXX")"
trap 'rm -rf "$test_build_dir"' EXIT

swiftc -parse-as-library -module-cache-path "$test_build_dir/ModuleCache" \
  "$repo_root/LexiBar/LLMService.swift" \
  "$repo_root/LexiBar/Prompts.swift" \
  "$repo_root/Tests/LLMServiceRegressionTests.swift" \
  -o "$test_build_dir/llm-regressions"
"$test_build_dir/llm-regressions"
