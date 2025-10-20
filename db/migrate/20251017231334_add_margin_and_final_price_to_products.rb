class AddMarginAndFinalPriceToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :margin, :decimal, precision: 5, scale: 2, default: 0.0
    add_column :products, :final_price, :decimal, precision: 10, scale: 2, default: 0.0
  end
end
