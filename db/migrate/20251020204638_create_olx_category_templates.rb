class CreateOlxCategoryTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :olx_category_templates do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :name
      t.references :olx_category, null: false, foreign_key: true
      t.references :olx_location, null: false, foreign_key: true
      t.string :default_listing_type
      t.string :default_state
      t.json :attribute_mappings

      t.timestamps
    end

    add_index :olx_category_templates, :name
  end
end
