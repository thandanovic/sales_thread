class AddDiscardedAtToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :discarded_at, :datetime
    add_index :products, :discarded_at
  end
end
