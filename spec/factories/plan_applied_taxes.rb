# frozen_string_literal: true

FactoryBot.define do
  factory :plan_applied_tax, class: "Plan::AppliedTax" do
    plan
    tax
    organization { plan&.organization || tax&.organization || association(:organization) }

    trait :catalog_plan do
      plan { nil }
      catalog_plan { association(:catalog_plan, organization:) }
    end
  end
end
