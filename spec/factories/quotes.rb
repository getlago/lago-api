# frozen_string_literal: true

FactoryBot.define do
  factory :quote do
    customer
    organization { customer&.organization || association(:organization) }

    trait :subscription_creation do
      order_type { :subscription_creation }
    end

    trait :subscription_amendment do
      order_type { :subscription_amendment }
    end

    trait :one_off do
      order_type { :one_off }
    end

    trait :approved do
      status { :approved }
      approved_at { Time.current }
    end

    trait :voided do
      status { :voided }
      voided_at { Time.current }
      void_reason { :manual }
    end
  end
end
