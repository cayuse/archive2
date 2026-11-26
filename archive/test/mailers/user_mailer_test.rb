require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "the welcome email goes to the user from the app's configured address" do
    user = User.new(name: "Test User", email: "test@example.com")
    email = UserMailer.welcome_email(user, "temp123")

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ ApplicationMailer.default[:from] ], email.from
    assert_equal [ "test@example.com" ], email.to
    assert_equal "Welcome to Music Archive - Your Account is Ready!", email.subject
    assert_match "Welcome to CavaForge Archive!", email.html_part.body.to_s
    assert_match "Welcome to Music Archive!", email.text_part.body.to_s
  end

  test "the welcome email carries the temporary password and a link to the site" do
    user = User.new(name: "Test User", email: "test@example.com")
    email = UserMailer.welcome_email(user, "temp123")

    [ email.html_part, email.text_part ].each do |part|
      assert_match "temp123", part.body.to_s
      assert_match "example.com", part.body.to_s
    end
  end
end
