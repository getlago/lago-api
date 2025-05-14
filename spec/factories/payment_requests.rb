# frozen_string_literal: true

FactoryBot.define do
  factory :payment_request do
    customer
    organization { customer.organization }

    amount_cents { 200 }
    amount_currency { "EUR" }
    email { Faker::Internet.email }
    payment_status { "pending" }
    ready_for_payment_processing { true }
    payment_attempts { 0 }

    transient do
      invoices { [] }
    end

    after(:create) do |payment_request, evaluator|
      evaluator.invoices.each do |invoice|
        PaymentRequest::AppliedInvoice.create!(payment_request:, invoice:)
      end
    end
  end
end
