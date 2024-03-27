# frozen_string_literal: true

FactoryBot.define do
  factory :plan_applied_tax, class: "Plan::AppliedTax" do
    plan
    tax
  end
end
