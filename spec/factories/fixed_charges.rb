FactoryBot.define do
  factory :fixed_charge do
    organization { nil }
    billing_entity { nil }
    plan { nil }
    add_on { nil }
    parent { nil }
    charge_model { "MyString" }
    properties { "" }
    invoice_display_name { "MyString" }
    pay_in_advance { false }
    prorated { false }
    recurring { false }
    billing_period_duration { 1 }
    billing_period_duration_unit { "MyString" }
    trial_period { 1 }
    untis { 1 }
  end
end
