FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    amount_cents { Faker::Number.between(from: 100, to: 500) }
    amount_currency { 'EUR' }
    
    pro_rata { false }

    factory :one_time_charge do
      frequency { :one_time }
    end

    factory :recurring_charge do
      frequency { :recurring }
    end
  end
end
