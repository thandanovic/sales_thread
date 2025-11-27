class AddSyncedAtToOlxListings < ActiveRecord::Migration[8.0]
  def change
    add_column :olx_listings, :synced_at, :datetime
  end
end
