# TODO: Email integration is not yet implemented.
#
# This is the base mailer class. To activate email functionality, an agent needs to:
#
# 1. Configure a mail delivery service. Add the following to config/environments/production.rb:
#      config.action_mailer.delivery_method = :smtp
#      config.action_mailer.smtp_settings = {
#        address: ENV["SMTP_HOST"],
#        port: 587,
#        user_name: ENV["SMTP_USERNAME"],
#        password: ENV["SMTP_PASSWORD"],
#        authentication: "plain",
#        enable_starttls_auto: true
#      }
#    For development, use :letter_opener or :test delivery method.
#
# 2. Set a real sender address. Replace "from@example.com" below with the app's
#    actual sending address (e.g. "AgentKVT <no-reply@yourdomain.com>").
#
# 3. Create concrete mailer classes that inherit from this one, e.g.:
#      class UserMailer < ApplicationMailer
#        def welcome_email(user)
#          @user = user
#          mail(to: @user.email, subject: "Welcome")
#        end
#      end
#    Pair each action with a view at app/views/user_mailer/welcome_email.html.erb
#    and app/views/user_mailer/welcome_email.text.erb.
#
# 4. Ensure User model has an email column (currently absent — add a migration).
#
# 5. Call mailers from jobs or controllers, e.g.:
#      UserMailer.welcome_email(@user).deliver_later
#
# Candidate emails to implement first:
#   - Mission completed notification
#   - Daily/weekly objective summary
#   - Action item due-date reminders
class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
end
