class AddDescriptionTemplateToOlxCategoryTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :olx_category_templates, :description_template, :text
  end
end
