require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "a visitor is turned away from settings" do
    get settings_path
    assert_redirected_to root_path
    assert_equal "Access denied. Admin privileges required.", flash[:error]
  end

  test "a regular user is turned away from settings" do
    sign_in users(:user)
    get settings_path
    assert_redirected_to root_path
    assert_equal "Access denied. Admin privileges required.", flash[:error]
  end

  test "a moderator is turned away from settings" do
    sign_in users(:moderator)
    get settings_path
    assert_redirected_to root_path
  end

  test "an admin sees the settings page" do
    sign_in users(:admin)
    get settings_path
    assert_response :success
  end

  test "an admin sees the general settings and the theme list" do
    sign_in users(:admin)
    get general_settings_path
    assert_response :success
    get manage_themes_path
    assert_response :success
  end

  test "a regular user cannot reach theme management" do
    sign_in users(:user)
    get manage_themes_path
    assert_redirected_to root_path
  end
end
