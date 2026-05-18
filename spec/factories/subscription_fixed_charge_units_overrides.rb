# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_fixed_charge_units_override do
    organization { subscription&.organization || association(:organization) }
    billing_entity { subscription&.billing_entity || association(:billing_entity) }
    subscription
    fixed_charge
    units { Faker::Number.between(from: 0, to: 100) }
  end
end
