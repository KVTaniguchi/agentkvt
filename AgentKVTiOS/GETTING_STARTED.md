# Run the iOS app in the Simulator

Follow these steps so the **Run** command (Play button) is available and the app launches in the iOS Simulator.

## 1. Open the Xcode project (not the folder)

- In Finder, go to the **AgentKVTiOS** folder.
- **Double‑click `AgentKVTiOS.xcodeproj`** to open it in Xcode.  
  Do **not** open the parent `agentkvt` folder in Xcode; that won’t give you a runnable project.

Or from Terminal:

```bash
open AgentKVTiOS/AgentKVTiOS.xcodeproj
```

(From the repo root, or use the full path to `AgentKVTiOS.xcodeproj`.)

## 2. Choose the app scheme

In the Xcode **toolbar**, use the **scheme** dropdown (left of the Play/Stop buttons):

- Choose **Run iOS App** or **AgentKVTiOS**.  
  Both run the iOS app.
- Do **not** choose **AgentKVTiOSTests** (that runs tests, not the app) or **AgentKVTMacApp** (Mac app).

If you pick a scheme that isn’t an app (e.g. tests or a library), the **Run** button may be disabled or may run tests instead of the app.

## 3. Choose an iPhone Simulator

In the **destination** dropdown (to the right of the scheme):

- Pick an **iPhone** simulator, e.g. **iPhone 17**, **iPhone 16e**, or **iPhone 15**.
- Do **not** leave it on **“My Mac (Designed for iPad)”** or **“Any iOS Device”** if you want the Simulator window to open and show the app.

## 4. Run the app

- Click the **Run** (Play) button in the toolbar, or press **⌘R**.
- The Simulator should start (if it isn’t already), and the app should launch.

---

## If you don’t see a Run command

- **Run is grayed out**
  - Make sure the **scheme** is **Run iOS App** or **AgentKVTiOS** (the app target), not the test target or Mac app.
  - **Product → Scheme → Edit Scheme… → Run (left) → Info**: set **Executable** to **AgentKVTiOS.app** and **Launch** to **Automatically**.
- **You opened a folder, not the project**
  - Close the window and open **`AgentKVTiOS.xcodeproj`** (the file) as in step 1.
- **No simulators in the destination list**
  - **Xcode → Settings → Platforms**: install an **iOS** simulator runtime, then pick an iPhone simulator again.

For more cases (e.g. “Build Succeeds” but nothing runs), see [RUN_TROUBLESHOOTING.md](RUN_TROUBLESHOOTING.md).
