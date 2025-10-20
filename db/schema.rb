# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_10_20_105057) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "import_logs", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.string "source"
    t.string "status"
    t.integer "total_rows"
    t.integer "processed_rows"
    t.integer "successful_rows"
    t.integer "failed_rows"
    t.text "metadata"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "error_messages"
    t.index ["shop_id"], name: "index_import_logs_on_shop_id"
  end

  create_table "imported_products", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.integer "import_log_id", null: false
    t.string "source"
    t.text "raw_data"
    t.string "status"
    t.text "error_text"
    t.integer "product_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["import_log_id"], name: "index_imported_products_on_import_log_id"
    t.index ["product_id"], name: "index_imported_products_on_product_id"
    t.index ["shop_id"], name: "index_imported_products_on_shop_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "shop_id", null: false
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_memberships_on_shop_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.string "source"
    t.string "source_id"
    t.string "title"
    t.string "sku"
    t.string "brand"
    t.string "category"
    t.decimal "price"
    t.string "currency"
    t.integer "stock"
    t.text "description"
    t.text "specs"
    t.boolean "published"
    t.string "olx_ad_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "margin", precision: 5, scale: 2, default: "0.0"
    t.decimal "final_price", precision: 10, scale: 2, default: "0.0"
    t.string "branch_availability"
    t.string "quantity"
    t.index ["shop_id"], name: "index_products_on_shop_id"
  end

  create_table "shops", force: :cascade do |t|
    t.string "name"
    t.text "settings"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "import_logs", "shops"
  add_foreign_key "imported_products", "import_logs"
  add_foreign_key "imported_products", "products"
  add_foreign_key "imported_products", "shops"
  add_foreign_key "memberships", "shops"
  add_foreign_key "memberships", "users"
  add_foreign_key "products", "shops"
end
