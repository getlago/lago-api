# frozen_string_literal: true

FactoryBot.define do
  factory :credit do
    invoice
    organization { invoice.organization }
    applied_coupon

    amount_cents { 200 }
    amount_currency { "EUR" }
  end

  factory :credit_note_credit, class: "Credit" do
    invoice
    organization { invoice.organization }
    credit_note { association(:credit_note, organization:, invoice:) }

    amount_cents { 200 }
    amount_currency { "EUR" }
  end

  factory :progressive_billing_invoice_credit, class: "Credit" do
    invoice
    organization { invoice.organization }
    progressive_billing_invoice { association(:invoice, organization:) }

    amount_cents { 200 }
    amount_currency { "EUR" }
  end
end
