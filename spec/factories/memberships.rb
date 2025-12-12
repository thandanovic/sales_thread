FactoryBot.define do
  factory :membership do
    association :user
    association :shop
    role { "agent" }

    trait :manager do
      role { "manager" }
    end

    trait :agent do
      role { "agent" }
    end
  end
end
