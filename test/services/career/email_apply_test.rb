require "test_helper"

# Ask-then-send, email only (D32): sends from the user's own linked
# mailbox, gated on the send scope, and refuses to guess a recipient.
class Career::EmailApplyTest < ActiveSupport::TestCase
  setup do
    Career::EmailApply.delivery_override = :test
    Mail::TestMailer.deliveries.clear
  end

  teardown { Career::EmailApply.delivery_override = nil }

  test "sends from the linked address with the resume attached" do
    resume = users(:one).documents.create!(title: "My resume")
    resume.file.attach(io: StringIO.new("resume bytes"), filename: "resume.pdf", content_type: "application/pdf")

    Career::EmailApply.new(
      user: users(:one), to: "jobs@acme.com", subject: "Application — Shift lead",
      body: "Dear hiring manager…", resume: resume
    ).call

    mail = Mail::TestMailer.deliveries.sole
    assert_equal [ "one@example.com" ], mail.from
    assert_equal [ "jobs@acme.com" ], mail.to
    assert_equal "Application — Shift lead", mail.subject
    assert_equal "resume.pdf", mail.attachments.first.filename
  end

  test "a switched-off send scope fails closed" do
    linked_accounts(:alice_email).update!(disabled_scopes: [ "send" ])

    error = assert_raises(Career::EmailApply::Error) do
      Career::EmailApply.new(user: users(:one), to: "jobs@acme.com", subject: "s", body: "b").call
    end
    assert_match(/switched off/, error.message)
    assert_empty Mail::TestMailer.deliveries
  end

  test "no linked email explains the setup path" do
    error = assert_raises(Career::EmailApply::Error) do
      Career::EmailApply.new(user: users(:two), to: "jobs@acme.com", subject: "s", body: "b").call
    end
    assert_match(/Link your email/, error.message)
  end

  test "a blank or mangled recipient never sends" do
    assert_raises(Career::EmailApply::Error) do
      Career::EmailApply.new(user: users(:one), to: "", subject: "s", body: "b").call
    end
    assert_raises(Career::EmailApply::Error) do
      Career::EmailApply.new(user: users(:one), to: "not-an-address", subject: "s", body: "b").call
    end
    assert_empty Mail::TestMailer.deliveries
  end
end
