require "test_helper"

class EmailSenderRulesControllerTest < ActionDispatch::IntegrationTest
  test "one click teaches a sender rule, and re-teaching replaces it" do
    sign_in_as users(:one)

    post email_sender_rules_path, params: { email: "Deals@Shop.example ", rule: "mute" }
    rule = users(:one).email_sender_rules.find_by!(email: "deals@shop.example")
    assert_equal "mute", rule.rule

    post email_sender_rules_path, params: { email: "deals@shop.example", rule: "vip" }
    assert_equal "vip", rule.reload.rule
    assert_equal 1, users(:one).email_sender_rules.count
  end

  test "rules are removable and per-user" do
    rule = users(:one).email_sender_rules.create!(email: "x@y.example", rule: "mute")

    sign_in_as users(:two)
    delete email_sender_rule_path(rule)
    assert_response :not_found

    sign_in_as users(:one)
    delete email_sender_rule_path(rule)
    assert_not EmailSenderRule.exists?(rule.id)
  end

  test "bad rules are rejected politely" do
    sign_in_as users(:one)

    post email_sender_rules_path, params: { email: "a@b.example", rule: "worship" }
    assert_equal 0, users(:one).email_sender_rules.count
    assert flash[:alert].present?
  end
end
