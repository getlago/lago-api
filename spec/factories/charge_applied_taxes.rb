# frozen_string_literal: true

FactoryBot.define do
  factory :charge_applied_tax, class: "Charge::AppliedTax" do
    charge
    tax
  end
end
