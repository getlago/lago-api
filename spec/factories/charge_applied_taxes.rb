# frozen_string_literal: true

FactoryBot.define do
  factory :charge_applied_tax, class: "Charge::AppliedTax" do
    charge { association(:standard_charge) }
    organization { charge.organization }
    tax { association(:tax, organization:) }
  end
end
