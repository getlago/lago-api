# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_activation_rule do
    subscription
    organization { subscription&.organization || association(:organization) }
    rule_type { "payment_required" }
    status { "pending" }

    trait :satisfied do
      status { "satisfied" }
    end

    trait :failed do
      status { "failed" }
    end

    trait :not_applicable do
      status { "not_applicable" }
    end

    trait :expired do
      status { "expired" }
    end

    trait :with_timeout do
      timeout_hours { 24 }
      expires_at { Time.current + 24.hours }
    end
  end
end
