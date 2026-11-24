class AddReleaseFieldsToAlbums < ActiveRecord::Migration[8.0]
  def change
    add_column :albums, :musicbrainz_release_id, :uuid
    add_index :albums, :musicbrainz_release_id, unique: true
    add_column :albums, :musicbrainz_release_group_id, :uuid
    add_index :albums, :musicbrainz_release_group_id
    add_column :albums, :artist_credit, :string
    add_column :albums, :sort_title, :string
    add_column :albums, :release_year, :integer
    add_column :albums, :original_release_year, :integer
    add_column :albums, :release_type, :string
    add_column :albums, :secondary_types, :string
    add_column :albums, :release_status, :string
    add_column :albums, :release_country, :string
    add_column :albums, :label, :string
    add_column :albums, :catalog_number, :string
    add_column :albums, :barcode, :string
    add_column :albums, :disc_total, :integer
    add_column :albums, :compilation, :boolean, null: false, default: false
  end
end
