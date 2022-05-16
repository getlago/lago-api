# frozen_string_literal: true

FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    amount_currency { 'EUR' }

    factory :standard_charge do
      charge_model { 'standard' }
      properties do
        { amount_cents: Faker::Number.between(from: 100, to: 500) }
      end
    end

    factory :graduated_charge do
      charge_model { 'graduated' }
      properties { [] }
    end

    factory :package_charge do
      charge_model { 'package' }
      properties do
        {
          amount_cents: 100,
          free_units: 10,
          package_size: 10,
        }
      end
    end
  end
end
