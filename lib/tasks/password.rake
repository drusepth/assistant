# The last way back in (D-instance-mail): the person who runs the server
# makes a reset link from its shell. It is what a solo household uses when
# its only admin forgets the password and the instance sends no mail.
#
#   bin/rails password:reset_link EMAIL=you@example.com
#   bin/kamal app exec -i "bin/rails password:reset_link EMAIL=you@example.com"
namespace :password do
  desc "Print a one-time password reset link for EMAIL (valid 24 hours)"
  task reset_link: :environment do
    email = ENV["EMAIL"].to_s.strip.downcase
    abort "Usage: bin/rails password:reset_link EMAIL=you@example.com" if email.blank?

    user = User.find_by(email_address: email)
    abort "No account uses #{email}. Accounts on this server: #{User.order(:email_address).pluck(:email_address).join(", ").presence || "none yet"}" unless user

    Rails.logger.warn("Password reset link issued for #{user.email_address} (##{user.id}) from the command line")
    token = user.handed_password_reset_token
    helpers = Rails.application.routes.url_helpers

    if AppHost.known?
      puts helpers.edit_password_url(token, **AppHost.url_options)
    else
      puts helpers.edit_password_path(token)
      warn "\nThat's the path only; put your server's address in front of it " \
           "(set APP_HOST to get the whole link next time)."
    end
    puts "\nIt works once and expires in 24 hours."
  end
end
