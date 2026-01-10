#!/bin/bash
#
# Test API Access for QuotaGuard
#
# This script runs the API integration tests to verify that you can
# fetch usage data from your Claude, OpenAI, Cursor, and Claude Code subscriptions.
#
# Usage:
#   ./scripts/test-api-access.sh           # Run all API tests (standalone Swift script)

set -e

# Project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Run the standalone Swift test script
swift scripts/APIAccessTest.swift
