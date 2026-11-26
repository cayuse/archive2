require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "the login page renders" do
    get login_path
    assert_response :success
    assert_select "form[action=?]", login_path
    assert_select "input[name=email]"
    assert_select "input[name=password]"
  end

  test "pages behind login send a visitor to the login page" do
    get root_path
    assert_redirected_to login_path
  end

  test "a valid login starts a session and redirects home" do
    user = users(:user)
    sign_in user
    assert_redirected_to root_path
    assert_equal user.id, session[:user_id]
    assert_equal "Welcome back, #{user.name}!", flash[:notice]

    get root_path
    assert_response :success
  end

  test "a wrong password is rejected" do
    sign_in users(:user), password: "not-the-password"
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_select ".alert", text: /Invalid email or password/

    get root_path
    assert_redirected_to login_path
  end

  test "an unknown email is rejected" do
    post login_path, params: { email: "nobody@musicarchive.com", password: "user123" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "logout ends the session" do
    sign_in users(:user)
    delete logout_path
    assert_redirected_to root_path
    assert_nil session[:user_id]

    get root_path
    assert_redirected_to login_path
  end

  test "logout also works as a plain link" do
    sign_in users(:user)
    get logout_path
    assert_redirected_to root_path
    assert_nil session[:user_id]
  end
end
