require "net/http"
require "json"

class OllamaClient
  BASE_URL = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  DEFAULT_MODEL = ENV.fetch("OLLAMA_MODEL", "llama4:latest")
  TOKEN_LOG_PATH = File.expand_path("~/Library/Logs/AgentKVT/token_usage.jsonl")

  # Sends a chat request to the local Ollama instance.
  # Returns the assistant's reply as a plain string.
  # Raises on non-2xx HTTP or network errors.
  def chat(messages:, model: DEFAULT_MODEL, format: nil)
    uri = URI("#{BASE_URL}/api/chat")
    body = { model: model, messages: messages, stream: false }
    body[:format] = format if format

    response = Net::HTTP.start(uri.host, uri.port, read_timeout: 300, open_timeout: 10) do |http|
      http.post(uri.path, body.to_json, "Content-Type" => "application/json")
    end
    raise "Ollama error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(response.body)
    log_token_usage(model: model, parsed: parsed)
    parsed.dig("message", "content") ||
      raise("Unexpected Ollama response shape: #{response.body}")
  end

  private

  def log_token_usage(model:, parsed:)
    input = parsed["prompt_eval_count"]
    output = parsed["eval_count"]
    return unless input || output
    entry = { ts: Time.now.utc.iso8601, provider: "ollama", model: model,
              input_tokens: input.to_i, output_tokens: output.to_i }.to_json
    FileUtils.mkdir_p(File.dirname(TOKEN_LOG_PATH))
    File.open(TOKEN_LOG_PATH, "a") { |f| f.puts(entry) }
  rescue => e
    Rails.logger.warn("TokenUsageLogger: #{e.message}") if defined?(Rails)
  end
end
