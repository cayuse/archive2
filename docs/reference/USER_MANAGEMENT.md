# User management

Accounts in The Archive: how they are created, how people log in, and what an admin can do
with them. Roles and permissions are in `PUNDIT_AUTHORIZATION.md`.

## Accounts

There is no self-registration. An admin creates every account.

`users` table: `id` (UUID), `email` (unique, lower-cased and trimmed before validation),
`name` (2–50 characters), `role` (integer: `user` 0, `moderator` 1, `admin` 2, `dj` 3),
`password_digest` (bcrypt, via `has_secure_password`), timestamps.

Deleting a user also deletes their playlists, stations, jukeboxes, station feedback and
playback grants.

## Logging in

| Route | |
|---|---|
| `GET /login` | the form |
| `POST /login` | `email`, `password`; sets `session[:user_id]` and redirects to `/` |
| `DELETE /logout` (also `GET /logout`) | clears the session |

Sessions are cookie sessions. There is no "forgot password" flow, no email verification, no
lockout and no session timeout. A user who forgets their password asks an admin to reset it.

API clients log in with `POST /api/v1/auth/login` and get a bearer token instead; see
`archive_api.md`.

## Admin: Manage Users

"Manage Users" in the navigation bar (`/users`), admins only. Routes: `resources :users`
without `show`, plus two password actions.

**Create** (`/users/new`): name, email and role. On save the app generates a 12-character
alphanumeric temporary password (`SecureRandom.alphanumeric(12)`) and emails it to the new
user (`UserMailer#welcome_email`, sent during the request). The password is not shown to the
admin.

**Edit** (`/users/:id/edit`): name, email, role, and one "Local playback" checkbox per
archive node that offers local playback (these are the playback grants that let the user
play on that node's speakers). The same page has:

- **Set password** (`PATCH /users/:id/set_password`): the admin types a new password
  (at least 6 characters) twice.
- **Reset password** (`POST /users/:id/reset_password`): generates a new temporary password
  and sends the welcome email again.

Both are written to the Rails log with the admin's and the user's email.

**Delete** (`DELETE /users/:id`): an admin cannot delete their own account.

## Profile

Every user can change their own name, email and password at `/profile/edit` (the avatar link
in the navigation bar). Leaving the password fields blank keeps the current password.
Nothing forces a user to change a temporary password (the welcome email says they will be
prompted on first login; they are not).

## Email

- **Development**: `letter_opener` opens each email in the browser.
- **Test**: the `:test` delivery method.
- **Production**: SMTP through AWS SES. Settings come from the environment
  (`config/deploy.yml`): `AWS_SES_SMTP_HOST`, `AWS_SES_SMTP_PORT`, `AWS_SES_SMTP_DOMAIN`,
  and the secrets `AWS_SES_SMTP_USERNAME` / `AWS_SES_SMTP_PASSWORD`. The sender is
  `MAILER_FROM_EMAIL` (default `noreply@cavaforge.net`); links in the email use `APP_HOST`.

The welcome email has HTML and text templates in `app/views/user_mailer/`.

## First admin

`bin/rails db:seed` creates `admin@musicarchive.com` with the password `admin123` (and the
default theme and site settings) if that user does not exist. Change the password, or the
email and password, straight away on any installation that is reachable by others.

From the console:

```ruby
User.create!(name: "Jane Doe", email: "jane@example.com", role: "admin",
             password: "…", password_confirmation: "…")

user.admin?             # admin
user.moderator?         # moderator or admin
user.dj?                # dj
user.can_host_jukebox?  # dj, moderator or admin
```

## Code

- `UsersController` — admin management and the password actions
- `SessionsController` — login and logout
- `ProfileController` — the user's own profile
- `User`, `UserPolicy`, `UserMailer`
- Tests: `test/controllers/users_controller_test.rb`, `sessions_controller_test.rb`,
  `test/policies/user_policy_test.rb`, `test/mailers/user_mailer_test.rb`
