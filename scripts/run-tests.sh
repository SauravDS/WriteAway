#!/bin/bash
set -e

echo "Compiling tests..."
xcrun swiftc Sources/WriteAway/Mounter.swift \
             Sources/WriteAway/DriveMonitor.swift \
             Sources/WriteAway/ShellUtility.swift \
             Tests/WriteAwayTests/WriteAwayTests.swift \
             -o .test_runner

echo "Running tests..."
./.test_runner

echo "Cleaning up..."
rm .test_runner
