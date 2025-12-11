class AddSubTitleToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :sub_title, :string
  end
end
