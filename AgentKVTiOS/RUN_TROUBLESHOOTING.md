# iOS app: Run & Simulator troubleshooting

When **Build Succeeds** but **nothing launches** or the **Simulator doesn’t show**, work through this checklist.

---

## 1. The active scheme isn’t an app

- **Symptom:** Build succeeds, nothing launches.
- **Why:** Frameworks, libraries, Swift packages, and test bundles aren’t runnable. Run on these targets only builds.
- **Fix:** In the toolbar’s **scheme** selector (left of the Play button), choose your **app** scheme (it has an app icon, not a puzzle piece or test diamond). Or use **Product > Scheme** to switch.

---

## 2. No iOS Simulator selected (or a “build-only” destination)

- **Symptom:** The destination shows **“Any iOS Device (arm64)”** or a physical device that’s not connected; build succeeds but nothing runs.
- **Why:** “Any iOS Device (arm64)” is a build-only destination. Xcode can compile but not run.
- **Fix:** In the **destination** dropdown (to the right of the scheme), pick a **simulator** (e.g. **iPhone 15 Pro**, **iPhone 17**). If you don’t see simulators, see **§4** below.

---

## 3. Running on “My Mac (Designed for iPad)” or Mac Catalyst

- **Symptom:** You expect the iOS Simulator, but the app runs as a native Mac window (or nothing launches if the app isn’t compatible).
- **Why:** The destination is set to run your iPad/iPhone app on your Mac instead of the simulator.
- **Fix:** Change the destination to an **iOS Simulator** device (e.g. **iPhone 15 Pro**, **iPhone 17**).

---

## 4. No iOS simulator runtimes installed

- **Symptom:** The simulator list is empty; Xcode never launches a simulator.
- **Why:** No iOS runtimes are available.
- **Fix:** **Xcode > Settings > Platforms**, install an iOS simulator runtime. Then choose a simulator as your destination.

---

## 5. Scheme Run settings (Executable / Launch)

- **Symptom:** Build completes, then Xcode just waits; simulator never launches.
- **Why:** In the scheme’s Run action, **Executable** can be set to **None**, or **Launch** can be set to **“Wait for executable to be launched.”**
- **Fix:**
  - **Product > Scheme > Edit Scheme… > Run > Info**
  - Set **Executable** to your app (e.g. **AgentKVTiOS.app**).
  - Set **Launch** to **Automatically** (not “Wait for executable to be launched”).
  - Leave **Debug executable** on (usually).

---

## 6. Supported Destinations don’t include iPhone/iPad

- **Symptom:** You can’t pick any iOS simulators; only Mac destinations appear.
- **Why:** The target’s **Supported Destinations** exclude iPhone/iPad.
- **Fix:** Select your app target > **General > Supported Destinations**. Ensure **iPhone** and/or **iPad** are checked.

---

## 7. Platform mismatch (watchOS / tvOS / visionOS or paired device)

- **Symptom:** Run builds but doesn’t launch an iPhone simulator.
- **Why:** The scheme might be for a watch-only app or extension that needs a paired iPhone simulator, or the scheme is for another platform.
- **Fix:** Pick the **correct app scheme** (e.g. **AgentKVTiOS**) and a valid destination (e.g. an iPhone simulator). For watch apps, use a paired iPhone + Apple Watch simulator.

---

## 8. Deployment target vs. runtime mismatch

- **Symptom:** The app targets a newer iOS than any installed simulator runtime; no compatible simulators show.
- **Fix:** Either lower the app’s **iOS Deployment Target** (Target > General > Deployment Info) to match an installed simulator, or install a newer simulator runtime (**Xcode > Settings > Platforms**).

---

## Quick checklist to get running

1. **Pick the app scheme**  
   Toolbar > scheme popup > choose your app (app icon).

2. **Pick a simulator destination**  
   Toolbar > destination popup > choose e.g. **“iPhone 15 Pro”** or **“iPhone 17”** (or any available simulator).  
   If none are listed: **Xcode > Settings > Platforms** and install an iOS runtime.

3. **Verify scheme Run settings**  
   **Product > Scheme > Edit Scheme… > Run > Info**  
   - **Executable:** Your app  
   - **Launch:** Automatically  
   - **Debug executable:** On (usually)

4. **Verify target supports iPhone/iPad**  
   **Target > General > Supported Destinations:** Check **iPhone** and/or **iPad**.

5. **Clean and reset (if needed)**  
   - Clean build folder: **⇧⌘K**  
   - Delete Derived Data (optional): **Xcode > Settings > Locations > Derived Data** > open in Finder > delete the project’s folder.  
   - Reset simulator (optional): Open the **Simulator** app > **Device > Erase All Content and Settings**.

---

## Build vs Run

- **Build:** Compiles only; good for catching errors without launching.
- **Run:** Builds, installs, and launches the app in the chosen simulator/device with the debugger attached. Use this to actually run the app.

---

## If you’re still stuck

Share:

- The **exact scheme and destination** shown in the toolbar.
- Whether you see **“Any iOS Device (arm64)”** or **“My Mac (Designed for iPad)”**.
- What happens after **Run** (e.g. “Build Succeeded” but no simulator; any status bar message).
- A screenshot of **Product > Scheme > Edit Scheme… > Run > Info**.

That will narrow down the cause and allow a targeted fix.
