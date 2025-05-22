# frozen_string_literal: true

FactoryBot.define do
  factory :plan_applied_tax, class: "Plan::AppliedTax" do
    plan
    tax { association(:tax, organization: plan.organization) }
    organization { plan.organization }
  end
end
