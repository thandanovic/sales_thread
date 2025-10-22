class CreateOlxListings < ActiveRecord::Migration[8.0]
  def change
    create_table :olx_listings do |t|
      t.references :product, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true
      t.string :external_listing_id
      t.string :status
      t.datetime :published_at
      t.json :metadata

      t.timestamps
    end

    add_index :olx_listings, :external_listing_id, unique: true
    add_index :olx_listings, :status
  end
end
