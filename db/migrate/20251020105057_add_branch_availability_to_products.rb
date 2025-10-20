class AddBranchAvailabilityToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :branch_availability, :string
    add_column :products, :quantity, :string
  end
end
