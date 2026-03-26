# LLM Throttling (GPU / Neural Engine Cap)

The macOS agent runs on a **dedicated machine** (e.g. Mac Studio). Operational configuration is tuned for maximum performance while keeping the system stable.

## Requirement (Dedicated Machine)

- Prefer a model size and host configuration that fit comfortably on the machine without swap thrash or repeated thermal instability.
- The agent runtime should remain **single-flight**: one mission or chat inference at a time.
- Keep the machine awake and available for unattended operation.

This project does **not** implement an application-level CPU/GPU/ANE throttle inside the agent code.

## Ollama

Ollama does not expose a built-in “max GPU %” setting. Use system-level or process-level limits when you need to cap:

1. **Environment (if supported by your Ollama build):**  
   Set `OLLAMA_NUM_GPU=0` to force CPU-only (no GPU), or rely on the options below.

2. **macOS Activity Monitor:**  
   Throttle the Ollama process via “Limit CPU” (or equivalent) to reduce load. This is manual.

3. **Alternative: Run Ollama in a cgroup or `nice`:**  
   On macOS, `nice -n 10 ollama serve` can lower CPU priority so that other processes get more time. This does not cap GPU.

4. **Apple Silicon / Metal:**  
   There is no standard way to cap GPU usage at a fixed % from user space. Options:
   - Use a model that fits in memory without thrashing (smaller models use less GPU).
   - Run fewer concurrent requests so that the LLM is not constantly at 100%.
   - On a dedicated Mac Studio, high utilization is acceptable as long as the system remains stable under the chosen model and mission cadence.

## LM Studio

Check LM Studio’s settings for:
- **Max GPU layers** or **GPU offload %** — tune for the installed model and available memory.
- **Context / batch size** — tune for your model and memory.

## Recommendation

- **Operational:** Run the mission scheduler so that only one mission runs at a time. Use mission cadence and model choice to manage sustained load.
- **Model choice:** Prefer a model that fits comfortably in memory (e.g. 8B–70B depending on hardware) to reduce swap and thrashing.
- **Availability:** Keep App Nap / system sleep disabled for the unattended runner so scheduled work and sync continue reliably.
- **Monitoring:** Use Activity Monitor (or `sudo powermetrics`) to observe GPU/ANE usage; if the system becomes unstable, reduce model size or mission frequency.

## Status

No application-level throttle is implemented in the agent code. Resource management is achieved by operational choices and runtime structure: one mission at a time, bounded trigger buffering, model sizing, and host/LLM configuration where available. Sleep prevention in the runner exists to improve unattended availability, not to reserve headroom for other interactive apps.
