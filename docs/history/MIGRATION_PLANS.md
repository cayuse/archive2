# Migration Plans

## Migration 1: Create Users Table ✅ COMPLETED

### Purpose
Create the foundation for user authentication and role-based authorization in the music archive application.

### Fields to Include
- `email` (string, unique, indexed) - User's email address for login
- `name` (string) - User's display name
- `password_digest` (string) - Encrypted password using bcrypt
- `role` (integer, default: 0) - User role for authorization
- `created_at` (datetime) - Account creation timestamp
- `updated_at` (datetime) - Last update timestamp

### Role Enum Values
- `0` - `user` (regular user, can view and create personal playlists)
- `1` - `moderator` (can manage content, moderate playlists)
- `2` - `admin` (full access, can manage users and system settings)

### Indexes
- Primary key on `id`
- Unique index on `email`
- Index on `role` for authorization queries

### Security Considerations
- Email must be unique and validated
- Password will be encrypted using bcrypt
- Role-based access control will be implemented with Pundit
- CSRF protection enabled by default in Rails

### Migration Command
```bash
bin/rails generate migration CreateUsers email:string:uniq name:string role:integer password_digest:string
```

### Model Associations (Future)
- `has_many :playlists` (user's personal playlists)
- `has_many :ratings` (user's song ratings)
- `has_many :reviews` (user's album reviews)

### Authorization Rules
- Users can only view and edit their own playlists
- Moderators can manage all playlists and moderate content
- Admins have full system access including user management

---

## Migration 2: Create Artists Table ✅ COMPLETED

### Purpose
Create the artists table to store musician/band information for the music archive.

### Fields to Include
- `name` (string, null: false) - Artist/band name
- `biography` (text) - Artist biography/description
- `country` (string) - Country of origin
- `formed_year` (integer) - Year the artist/band was formed
- `website` (string) - Official website URL
- `image_url` (string) - Artist image/photo URL
- `created_at` (datetime) - Record creation timestamp
- `updated_at` (datetime) - Last update timestamp

### Indexes
- Primary key on `id`
- Index on `name` for search performance
- Index on `country` for filtering
- Index on `formed_year` for chronological queries

### Validation Rules
- Name must be present and unique
- Country should be a valid country code (optional)
- Formed year should be reasonable (1900-2030)
- Website should be a valid URL format (optional)

### Migration Command
```bash
bin/rails generate migration CreateArtists name:string biography:text country:string formed_year:integer website:string image_url:string
```

### Model Associations (Future)
- `has_many :albums`
- `has_many :songs, through: :albums`
- `has_and_belongs_to_many :genres`

### Business Rules
- Artists can have multiple albums
- Artists can belong to multiple genres
- Artist names should be unique to avoid confusion
- Biography is optional but recommended for better user experience

---

## Migration 3: Create Genres Table ✅ COMPLETED

### Purpose
Create the genres table to categorize music by style and type.

### Fields to Include
- `name` (string, null: false) - Genre name (e.g., "Rock", "Jazz", "Hip Hop")
- `description` (text) - Genre description and characteristics
- `color` (string) - Hex color code for UI display
- `created_at` (datetime) - Record creation timestamp
- `updated_at` (datetime) - Last update timestamp

### Indexes
- Primary key on `id`
- Unique index on `name` for data integrity
- Index on `name` for search performance

### Validation Rules
- Name must be present and unique
- Color should be a valid hex color format (optional)
- Description is optional but recommended

### Migration Command
```bash
bin/rails generate migration CreateGenres name:string description:text color:string
```

### Model Associations (Future)
- `has_and_belongs_to_many :artists`
- `has_and_belongs_to_many :albums`
- `has_and_belongs_to_many :songs`

### Business Rules
- Genres can be assigned to multiple artists, albums, and songs
- Genre names should be unique to avoid confusion
- Color is optional but helps with UI organization
- Description helps users understand the genre characteristics

---

## Migration 4: Create Albums Table

### Purpose
Create the albums table to store album information and link to artists.

### Fields to Include
- `title` (string, null: false) - Album title
- `artist_id` (integer, null: false) - Foreign key to artists table
- `release_date` (date) - Album release date
- `description` (text) - Album description/review
- `cover_image_url` (string) - Album cover image URL
- `total_tracks` (integer) - Number of tracks on the album
- `duration` (integer) - Total album duration in seconds
- `created_at` (datetime) - Record creation timestamp
- `updated_at` (datetime) - Last update timestamp

### Indexes
- Primary key on `id`
- Foreign key index on `artist_id`
- Index on `title` for search performance
- Index on `release_date` for chronological queries
- Index on `total_tracks` for filtering

### Validation Rules
- Title must be present
- Artist must exist (foreign key constraint)
- Release date should be reasonable (1900-2030)
- Total tracks should be positive integer
- Duration should be positive integer

### Migration Command
```bash
bin/rails generate migration CreateAlbums title:string artist:references release_date:date description:text cover_image_url:string total_tracks:integer duration:integer
```

### Model Associations (Future)
- `belongs_to :artist`
- `has_many :songs`
- `has_and_belongs_to_many :genres`
- `has_many :reviews`

### Business Rules
- Albums must belong to an artist
- Albums can have multiple songs
- Albums can belong to multiple genres
- Album titles should be unique per artist (but not globally)
- Release date helps with chronological organization 