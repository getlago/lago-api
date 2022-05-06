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

    factory :graduacted_charge do
      charge_model { 'graduated' }
      properties { [] }
    end

    factory :graduated_charge do
      charge_model { 'graduated' }
      # TODO: remove after migration to properties for standard plan
      amount_cents { 0 }
      properties { [] }
    end
  end
end
