class ChangeProductIdNullableInImportedProducts < ActiveRecord::Migration[8.0]
  def change
    change_column_null :imported_products, :product_id, true
  end
end
