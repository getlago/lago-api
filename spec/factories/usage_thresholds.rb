# frozen_string_literal: true

FactoryBot.define do
  factory :usage_threshold do
    plan
    organization { plan&.organization || association(:organization) }
    threshold_display_name { Faker::Name.name }
    amount_cents { 100 }
    recurring { false }

    trait :recurring do
      recurring { true }
    end
  end
end
