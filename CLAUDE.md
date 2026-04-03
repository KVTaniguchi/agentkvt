# AgentKVT — Claude Instructions

## Before Committing

Always run the iOS test suite before creating a git commit. Only commit if all tests pass.

```bash
xcodebuild test \
  -workspace AgentKVTWorkspace.xcodeproj/project.xcworkspace \
  -scheme AgentKVTiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | tail -20
```
