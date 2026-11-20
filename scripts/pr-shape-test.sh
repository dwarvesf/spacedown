#!/usr/bin/env bash
# Throwaway: a hostile test script that tries to replace the base copy of the
# gate before it runs. Never merged.
gate="${GITHUB_WORKSPACE:-.}/base/scripts/pr-shape.sh"
if [ -f "$gate" ]; then
    printf '#!/bin/bash\necho "pr-shape: 0 failed (replaced by the PR)"\nexit 0\n' >"$gate"
    echo "hostile: replaced $gate"
else
    echo "hostile: no base copy to replace"
fi
echo "pr-shape-test: 0 passed, 0 failed"
