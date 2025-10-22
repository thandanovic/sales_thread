FactoryBot.define do
  factory :olx_category do
    external_id { 1 }
    name { "MyString" }
    slug { "MyString" }
    parent_id { 1 }
    has_shipping { false }
    has_brand { false }
  end
end
