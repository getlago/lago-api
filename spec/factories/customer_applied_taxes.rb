# frozen_string_literal: true

FactoryBot.define do
  factory :customer_applied_tax, class: "Customer::AppliedTax" do
    customer
    tax { association(:tax, organization:) }
    organization { customer.organization }
  end
end
