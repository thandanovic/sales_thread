class AddScrapingProgressToImportLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :import_logs, :current_phase, :string
    add_column :import_logs, :scraped_count, :integer
  end
end
