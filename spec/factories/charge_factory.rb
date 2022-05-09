FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    amount_currency { 'EUR' }

    charge_model { 'standard' }

    factory :standard_charge do
      charge_model { 'standard' }
      amount_cents { Faker::Number.between(from: 100, to: 500) }
    end
  end
end
