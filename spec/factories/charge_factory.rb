FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    amount_cents { Faker::Number.between(from: 100, to: 500) }
    amount_currency { 'EUR' }

    charge_model { 'standard' }
  end
end
