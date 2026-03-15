# LLM Throttling (GPU / Neural Engine Cap)

The macOS agent runs on a **dedicated machine** (e.g. Mac Studio). Operational configuration is tuned for maximum performance while keeping the system stable.

## Requirement (Dedicated Machine)

- **Allow up to 90% of available memory and GPU layers** for the runner.
- **Preserve ~10% compute headroom** so the system remains responsive.

(On a shared machine, you may cap lower, e.g. 80% / 20% headroom; see FOUNDATIONAL_PLAN §2 for that scenario.)

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
   - On a dedicated Mac Studio, **90% utilization** is acceptable; leave ~10% headroom via scheduling (one mission at a time, spaced runs).

## LM Studio

Check LM Studio’s settings for:
- **Max GPU layers** or **GPU offload %** — set to **90%** (or higher) on a dedicated machine for maximum performance.
- **Context / batch size** — tune for your model and memory.

## Recommendation

- **Operational:** Run the mission scheduler so that only one mission runs at a time; space out runs (e.g. every 5–10 minutes) to avoid sustained 100% usage.
- **Model choice:** Prefer a model that fits comfortably in memory (e.g. 8B–70B depending on hardware) to reduce swap and thrashing.
- **Monitoring:** Use Activity Monitor (or `sudo powermetrics`) to observe GPU/ANE usage; if the system becomes unresponsive, reduce model size or mission frequency.

## Status

No application-level throttle is implemented in the agent code. Throttling/limits are achieved by operational choices (scheduling, model size, one mission at a time) and, where available, host/LLM configuration (LM Studio GPU limits, `nice`, etc.). **For a dedicated Mac Studio, configure the LLM host for up to 90% utilization.**
