class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :source
      t.string :source_id
      t.string :title
      t.string :sku
      t.string :brand
      t.string :category
      t.decimal :price
      t.string :currency
      t.integer :stock
      t.text :description
      t.text :specs
      t.boolean :published
      t.string :olx_ad_id

      t.timestamps
    end
  end
end
