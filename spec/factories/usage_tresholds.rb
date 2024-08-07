# frozen_string_literal: true

FactoryBot.define do
  factory :usage_treshold do
    plan
    treshold_display_name { Faker::Name.name }
    amount_cents { 100 }
    amount_currency { "EUR" }
    recurring { false }

    trait :recurring do
      recurring { true }
    end
  end
end
