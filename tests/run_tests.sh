#!/bin/sh
# Run the AI Helpdesk test suite against a local mock HTTP server.
set -e
cd "$(dirname "$0")"
perl ai_mock_server.pl 19091 &
MOCK=$!
trap 'kill $MOCK 2>/dev/null' EXIT
sleep 1
perl ai_helpdesk_test.pl
