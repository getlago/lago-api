FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    amount_cents { Faker::Number.between(from: 100, to: 500) }
    amount_currency { 'EUR' }
    vat_rate { 20 }

    pro_rata { false }
    charge_model { 'standard' }

    factory :one_time_charge do
      frequency { :one_time }
    end

    factory :recurring_charge do
      frequency { :recurring }
    end
  end
end
