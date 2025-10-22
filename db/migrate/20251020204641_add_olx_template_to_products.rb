class AddOlxTemplateToProducts < ActiveRecord::Migration[8.0]
  def change
    add_reference :products, :olx_category_template, null: true, foreign_key: true
  end
end
