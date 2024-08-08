# frozen_string_literal: true

FactoryBot.define do
  factory :usage_threshold do
    plan
    threshold_display_name { Faker::Name.name }
    amount_cents { 100 }
    recurring { false }

    trait :recurring do
      recurring { true }
    end
  end
end
