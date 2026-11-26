require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  setup { @admin, @moderator, @user = users(:admin), users(:moderator), users(:user) }

  def policy(actor, record) = UserPolicy.new(actor, record)

  test "people can see themselves; only an admin manages accounts" do
    assert policy(@user, @user).show?
    [ @user, @moderator ].each do |actor|
      assert_not policy(actor, @admin).index?
      assert_not policy(actor, @user).update?
      assert_not policy(actor, User.new).create?
      assert_not policy(actor, @user).destroy?
      assert_not policy(actor, @user).manage_roles?
      assert_not policy(actor, @user).manage_password?
    end
    assert policy(@admin, @user).index?
    assert policy(@admin, @user).update?
    assert policy(@admin, User.new).create?
    assert policy(@admin, @user).manage_roles?
    assert policy(@admin, @user).manage_password?
  end

  test "an admin can delete others but not themselves" do
    assert policy(@admin, @user).destroy?
    assert_not policy(@admin, @admin).destroy?
  end

  test "the scope: an admin sees everyone, nobody else sees anyone" do
    assert_equal User.count, UserPolicy::Scope.new(@admin, User).resolve.count
    assert_equal 0, UserPolicy::Scope.new(@user, User).resolve.count
  end
end
