require "net/http"
require "json"

class OllamaClient
  BASE_URL = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  DEFAULT_MODEL = ENV.fetch("OLLAMA_MODEL", "qwen2.5")

  # Sends a chat request to the local Ollama instance.
  # Returns the assistant's reply as a plain string.
  # Raises on non-2xx HTTP or network errors.
  def chat(messages:, model: DEFAULT_MODEL, format: nil)
    uri = URI("#{BASE_URL}/api/chat")
    body = { model: model, messages: messages, stream: false }
    body[:format] = format if format

    response = Net::HTTP.post(uri, body.to_json, "Content-Type" => "application/json")
    raise "Ollama error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).dig("message", "content") ||
      raise("Unexpected Ollama response shape: #{response.body}")
  end
end
