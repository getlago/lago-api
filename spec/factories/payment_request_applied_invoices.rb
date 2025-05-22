# frozen_string_literal: true

FactoryBot.define do
  factory :payment_request_applied_invoice, class: "PaymentRequest::AppliedInvoice" do
    payment_request { association(:payment_request, organization:) }
    invoice
    organization { invoice.organization }
  end
end
