# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    customer
    organization { customer&.organization || association(:organization) }
    order_form { association(:order_form, customer:, organization:) }
    billing_snapshot { {items: []} }
    order_type { :subscription_creation }
    currency { "EUR" }
    status { :created }
  end
end
