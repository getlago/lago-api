# frozen_string_literal: true

FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    amount_currency { 'EUR' }

    factory :standard_charge do
      charge_model { 'standard' }
      properties do
        { amount: Faker::Number.between(from: 100, to: 500).to_s }
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
          amount: '100',
          free_units: 10,
          package_size: 10,
        }
      end
    end

    factory :percentage_charge do
      charge_model { 'percentage' }
      properties do
        {
          rate: '0.0555',
          fixed_amount: '2',
          fixed_amount_target: 'each_unit',
        }
      end
    end
  end
end
