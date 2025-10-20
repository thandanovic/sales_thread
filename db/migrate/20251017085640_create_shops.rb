class CreateShops < ActiveRecord::Migration[8.0]
  def change
    create_table :shops do |t|
      t.string :name
      t.text :settings

      t.timestamps
    end
  end
end
