require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "every role the model defines can be saved, the DJ included" do
    User.roles.each_key do |role|
      user = User.create!(name: "Role #{role}", email: "role-#{role}@example.com", password: "password123", role: role)
      assert_equal role, user.reload.role
    end
  end
end
