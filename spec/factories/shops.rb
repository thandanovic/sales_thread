FactoryBot.define do
  factory :shop do
    sequence(:name) { |n| "Shop #{n}" }
    settings { nil }
  end
end
