class AddOlxUserInfoToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :olx_user_id, :string
    add_column :shops, :olx_user_name, :string
  end
end
