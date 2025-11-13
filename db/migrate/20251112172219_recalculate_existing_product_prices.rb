class RecalculateExistingProductPrices < ActiveRecord::Migration[8.0]
  def up
    # Recalculate final_price for all existing products with proper rounding
    say_with_time "Recalculating final prices for all products with rounding..." do
      Product.find_each do |product|
        base_price = product.price || 0.0
        margin_percentage = product.margin || 0.0
        new_final_price = (base_price * (1 + margin_percentage / 100.0)).round(2)

        # Only update if the value changed (avoid unnecessary updates)
        if product.final_price != new_final_price
          product.update_column(:final_price, new_final_price)
        end
      end

      Product.count
    end
  end

  def down
    # No need to revert - prices will remain rounded
  end
end
