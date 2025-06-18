FactoryBot.define do
  factory :fixed_charge do
    organization { plan&.organization || association(:organization) }
    billing_entity { organization&.default_billing_entity || association(:billing_entity) }
    plan
    add_on
    invoice_display_name { Faker::Fantasy::Tolkien.location }
    billing_period_duration { 1 }
    billing_period_duration_unit { "month" }
    trial_period { 0 }
    untis { 1 }

    trait :standard do
      charge_model { "standard" }
      properties do
        {}
      end
    end

    trait :pay_in_advance do
      pay_in_advance { true }
    end

    trait :prorated do
      prorated { true }
    end

    trait :recurring do
      recurring { true }
    end
  end
end
