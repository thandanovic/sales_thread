class CreateImpersonationLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :impersonation_logs do |t|
      t.references :admin_user, null: false, foreign_key: { to_table: :users }
      t.references :impersonated_user, null: false, foreign_key: { to_table: :users }
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.string :reason

      t.timestamps
    end

    add_index :impersonation_logs, :started_at
    add_index :impersonation_logs, [:admin_user_id, :ended_at]
  end
end
