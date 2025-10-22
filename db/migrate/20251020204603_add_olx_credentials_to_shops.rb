class AddOlxCredentialsToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :olx_username, :string
    add_column :shops, :olx_password, :string
    add_column :shops, :olx_access_token, :text
    add_column :shops, :olx_token_expires_at, :datetime
  end
end
