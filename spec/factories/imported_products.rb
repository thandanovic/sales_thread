FactoryBot.define do
  factory :imported_product do
    shop { nil }
    import_log { nil }
    source { "MyString" }
    raw_data { "MyText" }
    status { "MyString" }
    error_text { "MyText" }
    product { nil }
  end
end
