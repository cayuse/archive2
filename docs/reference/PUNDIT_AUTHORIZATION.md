# Authorization

Who may do what in The Archive, and where the code decides it. Part of this is Pundit
policies (`archive/app/policies/`); the rest is role checks written directly in controllers.
Both are described here because neither is the whole picture.

For accounts and login see `USER_MANAGEMENT.md`. For API tokens see `archive_api.md`.

## Roles

`users.role` is an integer enum on `User`:

| Role | Value | `admin?` | `moderator?` | `can_host_jukebox?` |
|---|---|---|---|---|
| `user` | 0 | | | |
| `moderator` | 1 | | yes | yes |
| `admin` | 2 | yes | yes | yes |
| `dj` | 3 | | | yes |

`moderator?` is true for admins too, so "moderator" below always means moderator or admin.
`dj` is not part of that ladder: it only adds the ability to host jukeboxes and stations.

Note: `db/structure.sql` still carries the original `check_valid_role` constraint
(`role IN (0, 1, 2)`). A database that has that constraint will refuse to save a `dj`.

## What each role can do

| | user | dj | moderator | admin |
|---|---|---|---|---|
| Browse and play songs, artists, albums, genres | yes | yes | yes | yes |
| Own playlists; see public playlists | yes | yes | yes | yes |
| Edit own profile (name, email, password) | yes | yes | yes | yes |
| Stations and party jukeboxes | | yes | yes | yes |
| Upload songs, edit song tags, Maintenance page | | | yes | yes |
| Bulk Operations page (CSV import/export, bulk delete) | | | yes | yes |
| Delete a single song | | | | yes |
| Manage users | | | | yes |
| System settings, themes, Speakers (archive node) | | | | yes |

Playing on the archive's speakers is not a role: an admin grants it per user and per node
(`playback_grants`, `User#can_play_on?`), on the user's edit page.

A jukebox or station can only be managed by its owner, whatever their role. Party guests are
not users at all; they join with the jukebox's guest or admin code.

## Pundit policies

`ApplicationController` includes the `PunditAuthorization` concern, which includes
`Pundit::Authorization` and turns `Pundit::NotAuthorizedError` into a flash message
("You are not authorized to perform this action.") and a redirect back. API controllers that
include `EncryptedTokenAuthentication` use the token's user as `pundit_user` and answer
403 JSON (`{"success": false, "message": "Not authorized"}`) instead.

`ApplicationPolicy` **denies everything** by default. Each policy opens up what it needs.

| Policy | Rules |
|---|---|
| `SongPolicy` | `show?`, `download_audio?`: everyone. `create?`, `update?`, `edit?`, `upload?`, `upload_audio?`, `manage_metadata?`, `maintenance?`, `bulk_update?`: moderator. `destroy?`: admin. Scope: all songs. |
| `ArtistPolicy`, `AlbumPolicy`, `GenrePolicy` | Scope: all records. A few `manage_*?` rules (moderator). The standard rules are left denied; these models have no create/edit pages. |
| `PlaylistPolicy` | `show?`: public or own. `create?`: any logged-in user. `update?`, `edit?`, `manage_songs?`: owner. `destroy?`: owner or admin. Scope: admin all; a user their own plus public. |
| `UserPolicy` | `show?`: yourself. `index?`, `create?`, `update?`, `edit?`, `manage_roles?`, `manage_password?`: admin. `destroy?`: admin, and not yourself. Scope: admin all; everyone else none. |

### Where they are used

- `SongsController`: `policy_scope(Song)` for lists; `authorize @song` on show, edit, update,
  destroy; `authorize Song, :maintenance?` and `:bulk_update?`.
- `UploadController`: `authorize Song, :upload?` before every action.
- `ArtistsController`, `AlbumsController`, `GenresController`: `policy_scope` only.
- `UsersController`: `policy_scope(User)`, `authorize @user`, and `:manage_password?` for the
  two password actions (on top of its own admin check).
- `Api::V1::PlaylistsController`: `policy_scope(Playlist)`, `authorize @playlist`, and
  `:manage_songs?` for adding, removing and reordering songs.
- Views: `policy(@song).update?` / `.destroy?` / `.download_audio?` on the song page and rows,
  `policy(Song.new).upload_audio?` on the song list.

Controllers do not call `verify_authorized`, so an action that forgets `authorize` is not caught.

## Checks that are not Pundit

| Where | Check |
|---|---|
| Every web controller except login, themes' CSS/assets, the guest page and `/s/:token` | `authenticate_user!` (redirects to `/login`) |
| `UsersController`, `SettingsController`, `ArchiveNodesController` | their own `require_admin` (redirect to `/`) |
| `BulkOperationsController` | `current_user.moderator?` |
| `JukeboxesController`, `StationsController` | `current_user.can_host_jukebox?`; jukebox pages also require the owner |
| `PlaylistsController` (web) | `@playlist.owned_by?(current_user)` for changes |
| `ProfileController` | always acts on `current_user` |
| `Api::V1::SongsController#bulk_upload` | moderator |
| `Api::V1::JukeboxesController` | jukebox owner; `can_host_jukebox?` for station endpoints; `can_play_on?` for speaker playback |
| `Api::V1::NodePlayerController` | node token, or a user with a playback grant |
| `Api::V1::GuestController` | the jukebox's guest or admin code |
| Navigation bar | `can_host_jukebox?`, `moderator?`, `admin?` decide which links show |

`PunditAuthorization` also defines `can_manage_content?`, `can_manage_users?` and
`can_upload_audio?` (view helpers) and `require_moderator_or_admin`, `require_admin`,
`require_authenticated_user`. Nothing uses the helpers at present, and the controllers
listed above define their own `require_admin`.

## Tests

`archive/test/policies/` has `library_policies_test.rb` (songs, artists, albums, genres),
`playlist_policy_test.rb` and `user_policy_test.rb`.

## Adding a rule

```ruby
# app/policies/song_policy.rb
def retag?
  user&.moderator?
end

# controller
authorize @song, :retag?

# view
<% if policy(@song).retag? %> … <% end %>
```

Remember that a new policy inherits "deny" for every standard rule, and that a controller
action is only protected if it calls `authorize` (or has its own check).
