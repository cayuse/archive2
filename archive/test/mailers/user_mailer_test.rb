require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "welcome email can be created" do
    user = User.new(name: "Test User", email: "test@example.com")
    email = UserMailer.welcome_email(user, "temp123")
    
    assert_emails 1 do
      email.deliver_now
    end
    
    assert_equal ["noreply@musicarchive.com"], email.from
    assert_equal ["test@example.com"], email.to
    assert_equal "Welcome to Music Archive - Your Account is Ready!", email.subject
    assert_match "Welcome to Music Archive!", email.html_part.body.to_s
    assert_match "Welcome to Music Archive!", email.text_part.body.to_s
  end
end
