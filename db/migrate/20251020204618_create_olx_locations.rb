class CreateOlxLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :olx_locations do |t|
      t.integer :external_id
      t.string :name
      t.integer :country_id
      t.integer :state_id
      t.integer :canton_id
      t.decimal :lat
      t.decimal :lon
      t.string :zip_code

      t.timestamps
    end

    add_index :olx_locations, :external_id, unique: true
    add_index :olx_locations, :country_id
    add_index :olx_locations, :state_id
    add_index :olx_locations, :canton_id
  end
end
