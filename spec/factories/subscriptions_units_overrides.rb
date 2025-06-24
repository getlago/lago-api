# frozen_string_literal: true

FactoryBot.define do
  factory :subscriptions_units_override do
    subscription
    fixed_charge
    organization { subscription&.organization || fixed_charge&.organization || association(:organization) }
    units { Faker::Number.decimal(l_digits: 1, r_digits: 2) }
  end
end 