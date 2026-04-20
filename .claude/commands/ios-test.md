Run the AgentKVT iOS test suite and report results.

Run:
```
xcodebuild test \
  -workspace AgentKVTWorkspace.xcodeproj/project.xcworkspace \
  -scheme AgentKVTiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | tail -40
```

Report: number of tests passed/failed, any failing test names with file:line, and whether it is safe to commit.
