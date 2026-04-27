require "base64"

# Generates a plain-text description of each image attached to an objective using
# an Ollama vision model. Returns [] when no vision model is configured or the
# objective has no image attachments.
class ObjectiveImageDescriber
  VISION_MODEL = ENV["OLLAMA_VISION_MODEL"].presence
  MAX_IMAGES   = 3

  DESCRIBE_PROMPT = "Describe what is shown in this image clearly and concisely. Focus on objects, people, text, context, and any details that would be useful for planning a task related to this image."

  def initialize(client: OllamaClient.new)
    @client = client
  end

  def describe_all(objective)
    describe_files(objective.inbound_files, context_id: objective.id)
  end

  def describe_for_feedback(feedback)
    describe_files(feedback.inbound_files, context_id: feedback.id)
  end

  private

  def describe_files(files, context_id:)
    return [] if VISION_MODEL.nil?

    image_files = files
      .select { |f| f.content_type.to_s.start_with?("image/") }
      .first(MAX_IMAGES)

    return [] if image_files.empty?

    image_files.filter_map.with_index(1) do |file, index|
      describe(file, index)
    rescue => e
      Rails.logger.warn("[ObjectiveImageDescriber] context=#{context_id} file=#{file.id} error=#{e.message}")
      nil
    end
  end

  def describe(file, index)
    b64 = Base64.strict_encode64(file.file_data)
    content = @client.chat(
      model: VISION_MODEL,
      messages: [
        { role: "user", content: DESCRIBE_PROMPT, images: [b64] }
      ],
      task: "image-describe"
    )
    "Attached image #{index} (#{file.file_name}): #{content.to_s.strip}"
  end
end
