class UserMailer < ApplicationMailer
  def welcome_email(user, temporary_password)
    @user = user
    @temporary_password = temporary_password
    @login_url = root_url

    mail(
      to: @user.email,
      subject: "Welcome to The Archive - your account is ready"
    )
  end
end
