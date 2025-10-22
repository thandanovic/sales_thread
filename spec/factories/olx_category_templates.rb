FactoryBot.define do
  factory :olx_category_template do
    shop { nil }
    name { "MyString" }
    olx_category { nil }
    olx_location { nil }
    default_listing_type { "MyString" }
    default_state { "MyString" }
  end
end
