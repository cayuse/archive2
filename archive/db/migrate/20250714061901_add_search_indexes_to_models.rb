class AddSearchIndexesToModels < ActiveRecord::Migration[8.0]
  def up
    # Add search vectors to songs
    add_column :songs, :search_vector, :tsvector
    add_index :songs, :search_vector, using: :gin
    
    # Add search vectors to artists
    add_column :artists, :search_vector, :tsvector
    add_index :artists, :search_vector, using: :gin
    
    # Add search vectors to genres
    add_column :genres, :search_vector, :tsvector
    add_index :genres, :search_vector, using: :gin
    
    # Add search vectors to albums
    add_column :albums, :search_vector, :tsvector
    add_index :albums, :search_vector, using: :gin
    
    # Create triggers to automatically update search vectors
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_songs_search_vector()
      RETURNS trigger AS $$
      BEGIN
        NEW.search_vector := setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A');
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_artists_search_vector()
      RETURNS trigger AS $$
      BEGIN
        NEW.search_vector := 
          setweight(to_tsvector('english', COALESCE(NEW.name, '')), 'A') ||
          setweight(to_tsvector('english', COALESCE(NEW.biography, '')), 'B');
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_genres_search_vector()
      RETURNS trigger AS $$
      BEGIN
        NEW.search_vector := 
          setweight(to_tsvector('english', COALESCE(NEW.name, '')), 'A') ||
          setweight(to_tsvector('english', COALESCE(NEW.description, '')), 'B');
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_albums_search_vector()
      RETURNS trigger AS $$
      BEGIN
        NEW.search_vector := 
          setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
          setweight(to_tsvector('english', COALESCE(NEW.description, '')), 'B');
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
    
    # Create triggers for each table
    execute <<-SQL
      CREATE TRIGGER songs_search_vector_update
        BEFORE INSERT OR UPDATE ON songs
        FOR EACH ROW EXECUTE FUNCTION update_songs_search_vector();
    SQL
    
    execute <<-SQL
      CREATE TRIGGER artists_search_vector_update
        BEFORE INSERT OR UPDATE ON artists
        FOR EACH ROW EXECUTE FUNCTION update_artists_search_vector();
    SQL
    
    execute <<-SQL
      CREATE TRIGGER genres_search_vector_update
        BEFORE INSERT OR UPDATE ON genres
        FOR EACH ROW EXECUTE FUNCTION update_genres_search_vector();
    SQL
    
    execute <<-SQL
      CREATE TRIGGER albums_search_vector_update
        BEFORE INSERT OR UPDATE ON albums
        FOR EACH ROW EXECUTE FUNCTION update_albums_search_vector();
    SQL
    
    # Update existing records
    execute <<-SQL
      UPDATE songs SET search_vector = 
        setweight(to_tsvector('english', COALESCE(title, '')), 'A');
    SQL
    
    execute <<-SQL
      UPDATE artists SET search_vector = 
        setweight(to_tsvector('english', COALESCE(name, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(biography, '')), 'B');
    SQL
    
    execute <<-SQL
      UPDATE genres SET search_vector = 
        setweight(to_tsvector('english', COALESCE(name, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(description, '')), 'B');
    SQL
    
    execute <<-SQL
      UPDATE albums SET search_vector = 
        setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(description, '')), 'B');
    SQL
  end

  def down
    # Remove triggers
    execute "DROP TRIGGER IF EXISTS songs_search_vector_update ON songs;"
    execute "DROP TRIGGER IF EXISTS artists_search_vector_update ON artists;"
    execute "DROP TRIGGER IF EXISTS genres_search_vector_update ON genres;"
    execute "DROP TRIGGER IF EXISTS albums_search_vector_update ON albums;"
    
    # Remove functions
    execute "DROP FUNCTION IF EXISTS update_songs_search_vector();"
    execute "DROP FUNCTION IF EXISTS update_artists_search_vector();"
    execute "DROP FUNCTION IF EXISTS update_genres_search_vector();"
    execute "DROP FUNCTION IF EXISTS update_albums_search_vector();"
    
    # Remove columns
    remove_column :songs, :search_vector
    remove_column :artists, :search_vector
    remove_column :genres, :search_vector
    remove_column :albums, :search_vector
  end
end
