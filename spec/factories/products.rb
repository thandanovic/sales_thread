FactoryBot.define do
  factory :product do
    shop { nil }
    source { "MyString" }
    source_id { "MyString" }
    title { "MyString" }
    sku { "MyString" }
    brand { "MyString" }
    category { "MyString" }
    price { "9.99" }
    currency { "MyString" }
    stock { 1 }
    description { "MyText" }
    specs { "MyText" }
    published { false }
    olx_ad_id { "MyString" }
  end
end
