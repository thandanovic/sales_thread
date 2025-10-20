class AddErrorMessagesToImportLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :import_logs, :error_messages, :text
  end
end
