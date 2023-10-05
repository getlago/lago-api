# frozen_string_literal: true

FactoryBot.define do
  factory :charge do
    billable_metric
    plan
    invoice_display_name { Faker::Fantasy::Tolkien.location }

    factory :standard_charge do
      charge_model { 'standard' }
      properties do
        { amount: Faker::Number.between(from: 100, to: 500).to_s }
      end
    end

    factory :graduated_charge do
      charge_model { 'graduated' }
      properties do
        { graduated_ranges: [] }
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
          fixed_amount: '2',
        }
      end
    end

    factory :volume_charge do
      charge_model { 'volume' }
      properties do
        {
          volume_ranges: [
            { from_value: 0, to_value: 100, per_unit_amount: '2', flat_amount: '1' },
            { from_value: 101, to_value: nil, per_unit_amount: '1', flat_amount: '0' },
          ],
        }
      end
    end

    factory :graduated_percentage_charge do
      charge_model { 'graduated_percentage' }
      properties do
        {
          graduated_percentage_ranges: [
            {
              from_value: 0,
              to_value: 10,
              rate: '0',
              flat_amount: '200',
            },
            {
              from_value: 11,
              to_value: nil,
              rate: '0',
              flat_amount: '300',
            },
          ],
        }
      end
    end

    trait :pay_in_advance do
      pay_in_advance { true }
    end
  end
end
