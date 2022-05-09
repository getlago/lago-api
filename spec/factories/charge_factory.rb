FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    amount_currency { 'EUR' }

    factory :standard_charge do
      charge_model { 'standard' }
      amount_cents { Faker::Number.between(from: 100, to: 500) }
    end

    factory :graduated_charge do
      charge_model { 'graduated' }
      # TODO: remove after migration to properties for standard plan
      amount_cents { 0 }
      properties { [] }
    end
  end
end
