require "test_helper"

class LibraryPoliciesTest < ActiveSupport::TestCase
  setup { @user, @moderator, @admin = users(:user), users(:moderator), users(:admin) }

  test "songs: anyone may view and download, staff may add and change, only an admin may delete" do
    song = songs(:one)
    as = ->(who) { SongPolicy.new(who, song) }
    [ nil, @user, @moderator, @admin ].each { |who| assert as.(who).show? && as.(who).download_audio? }
    %i[create? update? edit? upload? upload_audio? manage_metadata? maintenance? bulk_update?].each do |rule|
      assert_not as.(nil).public_send(rule), "visitor #{rule}"
      assert_not as.(@user).public_send(rule), "user #{rule}"
      assert as.(@moderator).public_send(rule), "moderator #{rule}"
      assert as.(@admin).public_send(rule), "admin #{rule}"
    end
    assert_not as.(@moderator).destroy?
    assert as.(@admin).destroy?
  end

  { AlbumPolicy => [ Album, :albums, %i[manage_songs? manage_genres?] ],
    ArtistPolicy => [ Artist, :artists, nil ],
    GenrePolicy => [ Genre, :genres, %i[manage_songs? manage_artists? manage_albums?] ] }.each do |policy, (model, fixture, rules)|
    test "#{policy}: everyone's scope is the whole library; managing is for staff" do
      assert_equal model.count, policy::Scope.new(@user, model).resolve.count
      assert_equal model.count, policy::Scope.new(nil, model).resolve.count
      record = send(fixture, :one)
      (rules || policy.instance_methods(false).grep(/\Amanage_/)).each do |rule|
        assert_not policy.new(@user, record).public_send(rule), "user #{rule}"
        assert policy.new(@moderator, record).public_send(rule), "moderator #{rule}"
        assert policy.new(@admin, record).public_send(rule), "admin #{rule}"
      end
    end

    test "#{policy}: the standard rules are not opened up (nothing relies on them)" do
      record = send(fixture, :one)
      %i[show? create? update? destroy?].each { |rule| assert_not policy.new(@admin, record).public_send(rule), rule }
    end
  end
end
