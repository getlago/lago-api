# frozen_string_literal: true

FactoryBot.define do
  factory :add_on_applied_tax, class: "AddOn::AppliedTax" do
    add_on { association(:add_on, organization:) }
    tax { association(:tax, organization:) }
    organization
  end
end
