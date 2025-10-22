class CreateOlxCategoryAttributes < ActiveRecord::Migration[8.0]
  def change
    create_table :olx_category_attributes do |t|
      t.references :olx_category, null: false, foreign_key: true
      t.string :name
      t.string :attribute_type
      t.string :input_type
      t.boolean :required
      t.json :options

      t.timestamps
    end

    add_index :olx_category_attributes, :name
  end
end
