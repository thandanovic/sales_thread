FactoryBot.define do
  factory :import_log do
    shop { nil }
    source { "MyString" }
    status { "MyString" }
    total_rows { 1 }
    processed_rows { 1 }
    successful_rows { 1 }
    failed_rows { 1 }
    metadata { "MyText" }
    started_at { "2025-10-17 10:56:42" }
    completed_at { "2025-10-17 10:56:42" }
  end
end
