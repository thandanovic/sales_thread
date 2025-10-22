class AddExternalIdToOlxCategoryAttributes < ActiveRecord::Migration[8.0]
  def change
    add_column :olx_category_attributes, :external_id, :integer
  end
end
