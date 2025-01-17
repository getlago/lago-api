# frozen_string_literal: true

FactoryBot.define do
  factory :invoice_subscription do
    subscription
    invoice

    recurring { false }

    trait :boundaries do
      timestamp { Time.current }

      from_datetime { timestamp.beginning_of_month }
      to_datetime { timestamp.end_of_month }
      charges_from_datetime { from_datetime - 1.month }
      charges_to_datetime { to_datetime.end_of_month }
    end
  end
end
