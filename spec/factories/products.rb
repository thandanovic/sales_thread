FactoryBot.define do
  factory :product do
    association :shop
    source { "csv" }
    sequence(:source_id) { |n| "SRC-#{n}" }
    sequence(:title) { |n| "Product #{n}" }
    sequence(:sku) { |n| "SKU-#{n}" }
    brand { "Test Brand" }
    category { "Test Category" }
    price { "99.99" }
    currency { "BAM" }
    stock { 10 }
    description { "Test product description" }
    specs { nil }
    published { false }
    olx_ad_id { nil }
  end
end
