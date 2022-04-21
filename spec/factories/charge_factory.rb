FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    amount_cents { Faker::Number.between(from: 100, to: 500) }
    amount_currency { 'EUR' }
    vat_rate { 20 }

    pro_rata { false }
    charge_model { 'standard' }
  end
end
