require "test_helper"

class PlaylistPolicyTest < ActiveSupport::TestCase
  setup do
    @owner, @other, @admin = users(:user), users(:moderator), users(:admin)
    @private = Playlist.create!(name: "Mine", user: @owner, is_public: false)
    @public = Playlist.create!(name: "Everyone's", user: @owner, is_public: true)
  end

  def policy(user, playlist) = PlaylistPolicy.new(user, playlist)

  test "a private playlist is its owner's alone" do
    assert policy(@owner, @private).show?
    assert_not policy(@other, @private).show?
    assert_not policy(nil, @private).show?
  end

  test "a public playlist can be seen by anyone but changed only by its owner" do
    assert policy(@other, @public).show?
    assert policy(nil, @public).show?
    assert policy(@owner, @public).update?
    assert policy(@owner, @public).manage_songs?
    assert_not policy(@other, @public).update?
    assert_not policy(@other, @public).manage_songs?
    assert_not policy(@other, @public).destroy?
  end

  test "the owner or an admin may delete; anyone signed in may create" do
    assert policy(@owner, @private).destroy?
    assert policy(@admin, @private).destroy?
    assert policy(@other, Playlist.new).create?
    assert_not policy(nil, Playlist.new).create?
  end

  test "the scope: your own and public ones; an admin sees all; a visitor only public" do
    assert_equal [ @public, @private ].map(&:id).sort, PlaylistPolicy::Scope.new(@owner, Playlist).resolve.where(id: [ @public.id, @private.id ]).pluck(:id).sort
    assert_equal [ @public.id ], PlaylistPolicy::Scope.new(@other, Playlist).resolve.where(id: [ @public.id, @private.id ]).pluck(:id)
    assert_equal 2, PlaylistPolicy::Scope.new(@admin, Playlist).resolve.where(id: [ @public.id, @private.id ]).count
    assert_equal [ @public.id ], PlaylistPolicy::Scope.new(nil, Playlist).resolve.where(id: [ @public.id, @private.id ]).pluck(:id)
  end
end
