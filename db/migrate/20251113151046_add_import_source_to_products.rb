class AddImportSourceToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :import_source, :string, default: 'manual'
    add_index :products, :import_source
  end
end
