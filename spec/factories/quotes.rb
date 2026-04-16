# frozen_string_literal: true

FactoryBot.define do
  factory :quote do
    organization
    customer
    sequential_id { 1 }
    version { 1 }
    status { :draft }
    order_type { :subscription_creation }

    trait :approved do
      status { :approved }
      approved_at { Time.current }
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
