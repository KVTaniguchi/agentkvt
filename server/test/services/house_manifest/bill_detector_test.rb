require "test_helper"
require "securerandom"

module HouseManifest
  class BillDetectorTest < ActiveSupport::TestCase
    setup do
      @workspace = Workspace.create!(name: "Manifest Test", slug: "manifest-#{SecureRandom.hex(4)}")
    end

    def email(from: "noreply@example.com", subject: "Hello", body: "Nothing here.")
      @workspace.inbound_emails.create!(
        message_id:   SecureRandom.hex(8),
        from_address: from,
        subject:      subject,
        body_text:    body
      )
    end

    test "detects PECO by from_address domain" do
      result = BillDetector.call(email(from: "billing@peco.com"))
      assert result.detected
      assert_equal "PECO", result.utility
    end

    test "detects PECO by subject keyword" do
      result = BillDetector.call(email(subject: "Your PECO bill is ready"))
      assert result.detected
      assert_equal "PECO", result.utility
    end

    test "detects PECO from forwarded message body" do
      body = "---------- Forwarded message ---------\nFrom: PECO <noreply@peco.com>\nSubject: April Bill\n\nYour bill is $120.00"
      result = BillDetector.call(email(body: body))
      assert result.detected
      assert_equal "PECO", result.utility
    end

    test "detects PGW by from_address" do
      result = BillDetector.call(email(from: "no-reply@pgworks.com"))
      assert result.detected
      assert_equal "PGW", result.utility
    end

    test "detects PGW by subject keyword" do
      result = BillDetector.call(email(subject: "Philadelphia Gas Works — March Statement"))
      assert result.detected
      assert_equal "PGW", result.utility
    end

    test "detects PWD by from_address" do
      result = BillDetector.call(email(from: "water@phila.gov"))
      assert result.detected
      assert_equal "PWD", result.utility
    end

    test "detects PWD by subject keyword" do
      result = BillDetector.call(email(subject: "Philadelphia Water Department Bill Due"))
      assert result.detected
      assert_equal "PWD", result.utility
    end

    test "returns not detected for unrelated email" do
      result = BillDetector.call(email(from: "deals@amazon.com", subject: "Your order has shipped", body: "Package on its way!"))
      refute result.detected
      assert_nil result.utility
    end

    test "does not false-positive on partial keyword in body beyond 1 KB" do
      long_body = ("x" * 1025) + " PECO bill amount due"
      result = BillDetector.call(email(body: long_body))
      refute result.detected
    end
  end
end
