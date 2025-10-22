class CreateOlxCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :olx_categories do |t|
      t.integer :external_id
      t.string :name
      t.string :slug
      t.integer :parent_id
      t.boolean :has_shipping
      t.boolean :has_brand
      t.json :metadata

      t.timestamps
    end

    add_index :olx_categories, :external_id, unique: true
    add_index :olx_categories, :parent_id
    add_index :olx_categories, :slug
  end
end
