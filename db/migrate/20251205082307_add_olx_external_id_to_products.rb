class AddOlxExternalIdToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :olx_external_id, :string
  end
end
