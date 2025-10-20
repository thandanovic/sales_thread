class AddRefreshedAtToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :refreshed_at, :datetime
  end
end
