class AddTitleTemplateToOlxCategoryTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :olx_category_templates, :title_template, :string
  end
end
