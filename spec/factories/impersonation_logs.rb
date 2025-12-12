FactoryBot.define do
  factory :impersonation_log do
    association :admin_user, factory: [:user, :admin]
    association :impersonated_user, factory: :user
    started_at { Time.current }
    ended_at { nil }
    reason { "Testing" }

    trait :active do
      ended_at { nil }
    end

    trait :ended do
      ended_at { Time.current + 1.hour }
    end
  end
end
