# frozen_string_literal: true

FactoryBot.define do
  factory :group_property do
    charge
    group
    values do
      { amount: Faker::Number.between(from: 100, to: 500).to_s }
    end
  end
end
