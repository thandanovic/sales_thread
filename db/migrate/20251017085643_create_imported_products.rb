class CreateImportedProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :imported_products do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :import_log, null: false, foreign_key: true
      t.string :source
      t.text :raw_data
      t.string :status
      t.text :error_text
      t.references :product, null: false, foreign_key: true

      t.timestamps
    end
  end
end
