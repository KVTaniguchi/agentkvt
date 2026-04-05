require "net/http"
require "json"

class OllamaClient
  BASE_URL = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  DEFAULT_MODEL = ENV.fetch("OLLAMA_MODEL", "llama4:latest")

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

    JSON.parse(response.body).dig("message", "content") ||
      raise("Unexpected Ollama response shape: #{response.body}")
  end
end
