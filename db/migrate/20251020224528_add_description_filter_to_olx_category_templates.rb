class AddDescriptionFilterToOlxCategoryTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :olx_category_templates, :description_filter, :json
  end
end
