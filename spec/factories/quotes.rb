# frozen_string_literal: true

FactoryBot.define do
  factory :quote do
    organization
    customer
    version { 1 }
    status { :draft }
    order_type { :subscription_creation }

    trait :approved do
      status { :approved }
    end

    trait :voided do
      status { :voided }
    end
  end
end
