# frozen_string_literal: true

FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    factory :standard_charge do
      charge_model { 'standard' }
      properties do
        { amount: Faker::Number.between(from: 100, to: 500).to_s }
      end
    end

    factory :graduated_charge do
      charge_model { 'graduated' }
      properties do
        [
          {
            to_value: 1,
            from_value: 0,
            flat_amount: '0',
            per_unit_amount: '0',
          },
          {
            to_value: nil,
            from_value: 2,
            flat_amount: '0',
            per_unit_amount: '3200',
          },
        ]
      end
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
          fixed_amount: '2'
        }
      end
    end

    factory :volume_charge do
      charge_model { 'volume' }
      properties do
        {
          ranges: [
            { from_value: 0, to_value: 100, per_unit_amount: '2', flat_amount: '1' },
            { from_value: 101, to_value: nil, per_unit_amount: '1', flat_amount: '0' },
          ],
        }
      end
    end
  end
end
