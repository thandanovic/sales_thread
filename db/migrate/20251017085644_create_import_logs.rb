class CreateImportLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :import_logs do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :source
      t.string :status
      t.integer :total_rows
      t.integer :processed_rows
      t.integer :successful_rows
      t.integer :failed_rows
      t.text :metadata
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
