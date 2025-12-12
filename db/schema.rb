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

ActiveRecord::Schema[8.0].define(version: 2025_12_11_093103) do
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

  create_table "impersonation_logs", force: :cascade do |t|
    t.integer "admin_user_id", null: false
    t.integer "impersonated_user_id", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id", "ended_at"], name: "index_impersonation_logs_on_admin_user_id_and_ended_at"
    t.index ["admin_user_id"], name: "index_impersonation_logs_on_admin_user_id"
    t.index ["impersonated_user_id"], name: "index_impersonation_logs_on_impersonated_user_id"
    t.index ["started_at"], name: "index_impersonation_logs_on_started_at"
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
    t.integer "olx_category_template_id"
    t.string "current_phase"
    t.integer "scraped_count"
    t.index ["olx_category_template_id"], name: "index_import_logs_on_olx_category_template_id"
    t.index ["shop_id"], name: "index_import_logs_on_shop_id"
  end

  create_table "imported_products", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.integer "import_log_id", null: false
    t.string "source"
    t.text "raw_data"
    t.string "status"
    t.text "error_text"
    t.integer "product_id"
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

  create_table "olx_categories", force: :cascade do |t|
    t.integer "external_id"
    t.string "name"
    t.string "slug"
    t.integer "parent_id"
    t.boolean "has_shipping"
    t.boolean "has_brand"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_olx_categories_on_external_id", unique: true
    t.index ["parent_id"], name: "index_olx_categories_on_parent_id"
    t.index ["slug"], name: "index_olx_categories_on_slug"
  end

  create_table "olx_category_attributes", force: :cascade do |t|
    t.integer "olx_category_id", null: false
    t.string "name"
    t.string "attribute_type"
    t.string "input_type"
    t.boolean "required"
    t.json "options"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "external_id"
    t.index ["name"], name: "index_olx_category_attributes_on_name"
    t.index ["olx_category_id"], name: "index_olx_category_attributes_on_olx_category_id"
  end

  create_table "olx_category_templates", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.string "name"
    t.integer "olx_category_id", null: false
    t.integer "olx_location_id"
    t.string "default_listing_type"
    t.string "default_state"
    t.json "attribute_mappings"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "description_filter"
    t.string "title_template"
    t.text "description_template"
    t.index ["name"], name: "index_olx_category_templates_on_name"
    t.index ["olx_category_id"], name: "index_olx_category_templates_on_olx_category_id"
    t.index ["olx_location_id"], name: "index_olx_category_templates_on_olx_location_id"
    t.index ["shop_id"], name: "index_olx_category_templates_on_shop_id"
  end

  create_table "olx_listings", force: :cascade do |t|
    t.integer "product_id", null: false
    t.integer "shop_id", null: false
    t.string "external_listing_id"
    t.string "status"
    t.datetime "published_at"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "synced_at"
    t.index ["external_listing_id"], name: "index_olx_listings_on_external_listing_id", unique: true
    t.index ["product_id"], name: "index_olx_listings_on_product_id"
    t.index ["shop_id"], name: "index_olx_listings_on_shop_id"
    t.index ["status"], name: "index_olx_listings_on_status"
  end

  create_table "olx_locations", force: :cascade do |t|
    t.integer "external_id"
    t.string "name"
    t.integer "country_id"
    t.integer "state_id"
    t.integer "canton_id"
    t.decimal "lat"
    t.decimal "lon"
    t.string "zip_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canton_id"], name: "index_olx_locations_on_canton_id"
    t.index ["country_id"], name: "index_olx_locations_on_country_id"
    t.index ["external_id"], name: "index_olx_locations_on_external_id", unique: true
    t.index ["state_id"], name: "index_olx_locations_on_state_id"
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
    t.datetime "refreshed_at"
    t.integer "olx_category_template_id"
    t.json "image_urls"
    t.string "olx_title"
    t.text "olx_description"
    t.string "import_source", default: "manual"
    t.string "olx_external_id"
    t.string "sub_title"
    t.text "technical_description"
    t.text "models"
    t.index ["import_source"], name: "index_products_on_import_source"
    t.index ["olx_category_template_id"], name: "index_products_on_olx_category_template_id"
    t.index ["shop_id"], name: "index_products_on_shop_id"
  end

  create_table "shops", force: :cascade do |t|
    t.string "name"
    t.text "settings"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "olx_username"
    t.string "olx_password"
    t.text "olx_access_token"
    t.datetime "olx_token_expires_at"
    t.string "olx_user_id"
    t.string "olx_user_name"
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
    t.boolean "admin", default: false, null: false
    t.index ["admin"], name: "index_users_on_admin"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "impersonation_logs", "users", column: "admin_user_id"
  add_foreign_key "impersonation_logs", "users", column: "impersonated_user_id"
  add_foreign_key "import_logs", "olx_category_templates"
  add_foreign_key "import_logs", "shops"
  add_foreign_key "imported_products", "import_logs"
  add_foreign_key "imported_products", "products"
  add_foreign_key "imported_products", "shops"
  add_foreign_key "memberships", "shops"
  add_foreign_key "memberships", "users"
  add_foreign_key "olx_category_attributes", "olx_categories"
  add_foreign_key "olx_category_templates", "olx_categories"
  add_foreign_key "olx_category_templates", "olx_locations"
  add_foreign_key "olx_category_templates", "shops"
  add_foreign_key "olx_listings", "products"
  add_foreign_key "olx_listings", "shops"
  add_foreign_key "products", "olx_category_templates"
  add_foreign_key "products", "shops"
end
