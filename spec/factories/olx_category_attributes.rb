FactoryBot.define do
  factory :olx_category_attribute do
    olx_category { nil }
    name { "MyString" }
    attribute_type { "MyString" }
    input_type { "MyString" }
    required { false }
  end
end
