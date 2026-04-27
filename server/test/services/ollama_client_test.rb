require "test_helper"
require "net/http"

class OllamaClientTest < ActiveSupport::TestCase
  MESSAGES = [{ role: "user", content: "Hello" }].freeze

  def ollama_body(content: "Hello back!", input_tokens: 10, output_tokens: 5)
    {
      "message" => { "content" => content },
      "prompt_eval_count" => input_tokens,
      "eval_count" => output_tokens
    }
  end

  def fake_http_session(response_body)
    captured = {}
    http = Object.new
    http.define_singleton_method(:post) do |path, body, _headers|
      captured[:path] = path
      captured[:body] = JSON.parse(body)
      resp = Net::HTTPSuccess.new("1.1", "200", "OK")
      resp.instance_variable_set(:@body, response_body.to_json)
      resp.instance_variable_set(:@read, true)
      resp
    end
    [http, captured]
  end

  def fake_error_http_session(code: "400")
    http = Object.new
    http.define_singleton_method(:post) do |_path, _body, _headers|
      resp = Net::HTTPClientError.new("1.1", code, "Bad Request")
      resp.instance_variable_set(:@body, "error")
      resp.instance_variable_set(:@read, true)
      resp
    end
    http
  end

  def with_fake_http(http)
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*_a, **_kw, &blk| blk.call(http) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, &original)
  end

  # --- chat happy path ---

  test "returns message content on success" do
    http, _captured = fake_http_session(ollama_body(content: "Hi there!"))
    with_fake_http(http) do
      result = OllamaClient.new.chat(messages: MESSAGES)
      assert_equal "Hi there!", result
    end
  end

  test "raises on non-2xx response" do
    with_fake_http(fake_error_http_session) do
      assert_raises(RuntimeError) do
        OllamaClient.new.chat(messages: MESSAGES)
      end
    end
  end

  test "raises when response body has no message.content" do
    http, _ = fake_http_session({ "model" => "x" })
    with_fake_http(http) do
      assert_raises(RuntimeError) do
        OllamaClient.new.chat(messages: MESSAGES)
      end
    end
  end

  # --- Request body fields ---

  test "includes model field in request body" do
    http, captured = fake_http_session(ollama_body)
    with_fake_http(http) do
      OllamaClient.new.chat(messages: MESSAGES, model: "test-model:latest")
    end
    assert_equal "test-model:latest", captured[:body]["model"]
  end

  test "stream is always false" do
    http, captured = fake_http_session(ollama_body)
    with_fake_http(http) do
      OllamaClient.new.chat(messages: MESSAGES)
    end
    assert_equal false, captured[:body]["stream"]
  end

  test "includes format when provided" do
    http, captured = fake_http_session(ollama_body)
    with_fake_http(http) do
      OllamaClient.new.chat(messages: MESSAGES, format: "json")
    end
    assert_equal "json", captured[:body]["format"]
  end

  test "omits format when not provided" do
    http, captured = fake_http_session(ollama_body)
    with_fake_http(http) do
      OllamaClient.new.chat(messages: MESSAGES)
    end
    assert_not captured[:body].key?("format")
  end

  test "includes options when non-empty" do
    http, captured = fake_http_session(ollama_body)
    with_fake_http(http) do
      OllamaClient.new.chat(messages: MESSAGES, options: { num_ctx: 4096 })
    end
    assert_equal({ "num_ctx" => 4096 }, captured[:body]["options"])
  end

  test "passes messages to Ollama" do
    http, captured = fake_http_session(ollama_body)
    with_fake_http(http) do
      OllamaClient.new.chat(messages: MESSAGES)
    end
    assert_equal [{ "role" => "user", "content" => "Hello" }], captured[:body]["messages"]
  end

  # --- Token logging ---

  test "silently continues when token log write fails" do
    http, _captured = fake_http_session(ollama_body(content: "Done"))
    orig_mkdir_p = FileUtils.method(:mkdir_p)
    FileUtils.define_singleton_method(:mkdir_p) { |_path| raise Errno::EACCES, "denied" }
    with_fake_http(http) do
      result = OllamaClient.new.chat(messages: MESSAGES)
      assert_equal "Done", result
    end
  ensure
    FileUtils.define_singleton_method(:mkdir_p, &orig_mkdir_p)
  end
end
