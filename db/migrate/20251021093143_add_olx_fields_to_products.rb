class AddOlxFieldsToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :olx_title, :string
    add_column :products, :olx_description, :text
  end
end
