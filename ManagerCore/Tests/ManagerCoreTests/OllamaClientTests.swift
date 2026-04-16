import Foundation
import Testing
import ManagerCore

struct OllamaClientTests {

    @Test("chat response decodes tool arguments when Ollama returns an object")
    func decodesObjectToolArguments() throws {
        let json = """
        {
          "message": {
            "role": "assistant",
            "content": null,
            "tool_calls": [
              {
                "type": "function",
                "function": {
                  "name": "web_search_and_fetch",
                  "arguments": {
                    "title": "Review test",
                    "systemIntent": "url.open"
                  }
                }
              }
            ]
          },
          "done": true
        }
        """

        let response = try JSONDecoder().decode(OllamaClient.ChatResponse.self, from: Data(json.utf8))
        let arguments = response.message?.toolCalls?.first?.function?.arguments

        #expect(arguments == #"{"systemIntent":"url.open","title":"Review test"}"# || arguments == #"{"title":"Review test","systemIntent":"url.open"}"#)
    }

    @Test("chat response decodes tool arguments when Ollama returns a string")
    func decodesStringToolArguments() throws {
        let json = """
        {
          "message": {
            "role": "assistant",
            "content": null,
            "tool_calls": [
              {
                "type": "function",
                "function": {
                  "name": "web_search_and_fetch",
                  "arguments": "{\\"title\\":\\"Review test\\",\\"systemIntent\\":\\"url.open\\"}"
                }
              }
            ]
          },
          "done": true
        }
        """

        let response = try JSONDecoder().decode(OllamaClient.ChatResponse.self, from: Data(json.utf8))
        let arguments = response.message?.toolCalls?.first?.function?.arguments

        #expect(arguments == #"{"title":"Review test","systemIntent":"url.open"}"#)
    }
}
