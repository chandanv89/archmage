#!/usr/bin/env bash
# Deprecated alias: use ./archmage instead.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/archmage" "$@"
