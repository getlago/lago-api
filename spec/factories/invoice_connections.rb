# frozen_string_literal: true

FactoryBot.define do
  factory :invoice_connection do
    invoice
    organization { invoice&.organization || association(:organization) }
    category { "payment" }
    payment_provider_customer do
      association(:stripe_customer, customer: invoice&.customer, organization:)
    end
  end
end
