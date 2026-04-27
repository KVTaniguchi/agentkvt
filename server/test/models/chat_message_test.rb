require "test_helper"
require "securerandom"

class ChatMessageTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Msg WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @thread = @workspace.chat_threads.create!(title: "Test Thread")
  end

  def valid_message(overrides = {})
    @thread.chat_messages.new({
      role: "user",
      content: "Hello",
      status: "pending",
      timestamp: Time.current
    }.merge(overrides))
  end

  test "valid with required fields" do
    msg = valid_message
    assert msg.valid?, msg.errors.full_messages.inspect
  end

  test "invalid without role" do
    msg = valid_message(role: nil)
    assert_not msg.valid?
    assert msg.errors[:role].any?
  end

  test "invalid role rejected" do
    msg = valid_message(role: "hacker")
    assert_not msg.valid?
    assert msg.errors[:role].any?
  end

  test "all valid roles accepted" do
    ChatMessage::ROLES.each do |role|
      msg = valid_message(role: role)
      assert msg.valid?, "Expected #{role} to be valid: #{msg.errors.full_messages}"
    end
  end

  test "invalid without content" do
    msg = valid_message(content: nil)
    assert_not msg.valid?
    assert msg.errors[:content].any?
  end

  test "invalid status rejected" do
    msg = valid_message(status: "invisible")
    assert_not msg.valid?
    assert msg.errors[:status].any?
  end

  test "all valid statuses accepted" do
    ChatMessage::STATUSES.each do |s|
      msg = valid_message(status: s)
      assert msg.valid?, "Expected #{s} to be valid: #{msg.errors.full_messages}"
    end
  end

  # --- Scopes ---

  test "chronological orders by timestamp asc" do
    msg1 = @thread.chat_messages.create!(role: "user", content: "First", status: "pending", timestamp: 2.minutes.ago)
    msg2 = @thread.chat_messages.create!(role: "assistant", content: "Second", status: "completed", timestamp: 1.minute.ago)

    ids = @thread.chat_messages.chronological.map(&:id)
    assert ids.index(msg1.id) < ids.index(msg2.id)
  end
end
