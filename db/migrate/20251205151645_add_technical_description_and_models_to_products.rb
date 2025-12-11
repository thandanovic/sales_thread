class AddTechnicalDescriptionAndModelsToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :technical_description, :text
    add_column :products, :models, :text
  end
end
