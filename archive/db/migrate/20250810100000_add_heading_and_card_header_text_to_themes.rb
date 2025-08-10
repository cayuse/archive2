class AddHeadingAndCardHeaderTextToThemes < ActiveRecord::Migration[8.0]
  def change
    add_column :themes, :heading_color, :string
    add_column :themes, :card_header_text, :string
  end
end


