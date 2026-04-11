require "net/http"
require "json"

class OllamaClient
  BASE_URL = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  DEFAULT_MODEL = ENV.fetch("OLLAMA_MODEL", "llama4:latest")
  TOKEN_LOG_PATH = File.expand_path("~/Library/Logs/AgentKVT/token_usage.jsonl")

  # Sends a chat request to the local Ollama instance.
  # Returns the assistant's reply as a plain string.
  # Raises on non-2xx HTTP or network errors.
  def chat(messages:, model: DEFAULT_MODEL, format: nil, task: nil, options: {})
    uri = URI("#{BASE_URL}/api/chat")
    body = { model: model, messages: messages, stream: false }
    body[:format] = format if format
    body[:options] = options if options.any?

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = Net::HTTP.start(uri.host, uri.port, read_timeout: 300, open_timeout: 10) do |http|
      http.post(uri.path, body.to_json, "Content-Type" => "application/json")
    end
    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
    raise "Ollama error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(response.body)
    log_token_usage(model: model, parsed: parsed, latency_ms: latency_ms, task: task)
    parsed.dig("message", "content") ||
      raise("Unexpected Ollama response shape: #{response.body}")
  end

  private

  INPUT_RATE_PER_M  = 3.00   # USD per 1M input tokens (Claude Sonnet baseline)
  OUTPUT_RATE_PER_M = 15.00  # USD per 1M output tokens

  def log_token_usage(model:, parsed:, latency_ms:, task: nil)
    input  = parsed["prompt_eval_count"]
    output = parsed["eval_count"]
    return unless input || output
    input  = input.to_i
    output = output.to_i
    savings = ((input / 1_000_000.0 * INPUT_RATE_PER_M) + (output / 1_000_000.0 * OUTPUT_RATE_PER_M)).round(6)
    entry = {
      ts:          Time.now.utc.iso8601,
      model:       model,
      task:        task || "unknown",
      tokens:      { in: input, out: output },
      latency_ms:  latency_ms,
      savings_usd: savings
    }.to_json
    FileUtils.mkdir_p(File.dirname(TOKEN_LOG_PATH))
    File.open(TOKEN_LOG_PATH, "a") { |f| f.puts(entry) }
  rescue => e
    Rails.logger.warn("TokenUsageLogger: #{e.message}") if defined?(Rails)
  end
end
