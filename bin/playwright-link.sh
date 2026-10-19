#!/bin/bash

# Link the system-wide Playwright install into the current project so
# require('playwright') / import { test } from '@playwright/test' resolve
# without any npm download (the browsers are already installed system-wide).
# A project's own node_modules copy is never overwritten.
#
# Usage: playwright-link [project-dir]      (default: current directory)

set -euo pipefail

GLOBAL=/usr/lib/node_modules

cd "${1:-.}"

mkdir -p node_modules/@playwright

link() {
    if [ -e "node_modules/$1" ] || [ -L "node_modules/$1" ]; then
        echo "keeping existing node_modules/$1"
    else
        ln -s "$GLOBAL/$1" "node_modules/$1"
        echo "linked node_modules/$1 -> $GLOBAL/$1"
    fi
}

link playwright
link @playwright/test
