# frozen_string_literal: true

FactoryBot.define do
  factory :flutterwave_payment, class: "PaymentProviders::FlutterwaveProvider::FlutterwavePayment" do
    skip_create
    initialize_with { new(id:, status:, metadata:) }

    id { "flw_payment_123" }
    status { nil }
    metadata { {} }
  end
end
