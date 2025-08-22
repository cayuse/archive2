class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM_EMAIL", "noreply@cavaforge.net")
  layout "mailer"
end
