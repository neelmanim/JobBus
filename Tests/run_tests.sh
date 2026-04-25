#!/bin/bash
# JobBus Unit Test Runner
set -e
cd "$(dirname "$0")/.."

echo "🔨 Compiling tests..."
mkdir -p .build

# Collect source files, excluding DOCX parser (needs ZIPFoundation)
SOURCES=$(find Sources/Models Sources/Protocols Sources/Services Sources/Providers \
    -name '*.swift' \
    ! -name 'DOCXParserService.swift' \
    | sort)

swiftc -o .build/test_runner \
    $SOURCES \
    Tests/JobBusTests.swift \
    -sdk $(xcrun --show-sdk-path) \
    2>&1

echo "🧪 Running tests..."
.build/test_runner
