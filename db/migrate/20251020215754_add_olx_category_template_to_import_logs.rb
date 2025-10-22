class AddOlxCategoryTemplateToImportLogs < ActiveRecord::Migration[8.0]
  def change
    add_reference :import_logs, :olx_category_template, foreign_key: true, null: true
  end
end
