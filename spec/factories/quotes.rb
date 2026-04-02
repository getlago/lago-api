# frozen_string_literal: true

FactoryBot.define do
  factory :quote do
    customer
    organization { customer&.organization || association(:organization) }
    order_type { :subscription_creation }
    currency { "EUR" }
    status { :approved }

    trait :draft do
      status { :draft }
    end

    trait :voided do
      status { :voided }
      voided_at { Time.current }
      void_reason { :manual }
    end

    trait :auto_execute do
      auto_execute { true }
    end
  end
end
