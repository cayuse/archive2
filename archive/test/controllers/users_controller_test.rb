require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "the users list needs a login" do
    get users_path
    assert_redirected_to login_path
  end

  test "a regular user is turned away from the users list" do
    sign_in users(:user)
    get users_path
    assert_redirected_to root_path
    assert_equal "Admin access required.", flash[:alert]
  end

  test "a moderator is turned away from the users list" do
    sign_in users(:moderator)
    get users_path
    assert_redirected_to root_path
  end

  test "an admin sees the users list" do
    sign_in users(:admin)
    get users_path
    assert_response :success
    User.pluck(:email).each { |email| assert_includes response.body, email }
  end

  test "an admin sees the new user form" do
    sign_in users(:admin)
    get new_user_path
    assert_response :success
  end

  test "an admin creates a user, who is emailed a temporary password" do
    sign_in users(:admin)
    assert_difference "User.count", 1 do
      assert_emails 1 do
        post users_path, params: { user: { name: "New Person", email: "new@example.com", role: "user" } }
      end
    end
    assert_redirected_to users_path
    created = User.find_by!(email: "new@example.com")
    assert created.user?
    assert_equal [ "new@example.com" ], ActionMailer::Base.deliveries.last.to
  end

  test "an invalid user is not created" do
    sign_in users(:admin)
    assert_no_difference "User.count" do
      assert_no_emails do
        post users_path, params: { user: { name: "", email: "not-an-email", role: "user" } }
      end
    end
    assert_response :unprocessable_entity
  end

  test "a regular user cannot create users" do
    sign_in users(:user)
    assert_no_difference "User.count" do
      post users_path, params: { user: { name: "New Person", email: "new@example.com", role: "admin" } }
    end
    assert_redirected_to root_path
  end

  test "a regular user cannot edit or delete another user" do
    sign_in users(:user)
    get edit_user_path(users(:moderator))
    assert_redirected_to root_path
    assert_no_difference "User.count" do
      delete user_path(users(:moderator))
    end
    assert_redirected_to root_path
  end

  test "a regular user cannot reset someone's password" do
    sign_in users(:user)
    target = users(:moderator)
    assert_no_emails do
      post reset_password_user_path(target)
    end
    assert_redirected_to root_path
    assert target.reload.authenticate("moderator123")
  end

  test "an admin updates a user" do
    sign_in users(:admin)
    patch user_path(users(:user)), params: { user: { name: "Renamed User" } }
    assert_redirected_to users_path
    assert_equal "Renamed User", users(:user).reload.name
  end
end
