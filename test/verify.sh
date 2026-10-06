#!/bin/bash
# Run the multi-session check against the installed wrapper.
exec node "$(cd "$(dirname "$0")" && pwd)/verify.cjs" "$@"
