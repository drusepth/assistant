# Instance mail is off unless the operator set SMTP_* (D-instance-mail), and
# the suite runs with it off. Tests that exercise the "this server sends
# email" path turn it on for a block; deliveries still land in the :test
# mailer, because InstanceMail.apply! never touches the test environment.
module InstanceMailTestHelper
  def with_instance_mail(address: "smtp.example.com")
    previous = ENV["SMTP_ADDRESS"]
    ENV["SMTP_ADDRESS"] = address
    yield
  ensure
    previous.nil? ? ENV.delete("SMTP_ADDRESS") : ENV["SMTP_ADDRESS"] = previous
  end
end

ActiveSupport.on_load(:active_support_test_case) { include InstanceMailTestHelper }
