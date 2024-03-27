# frozen_string_literal: true

FactoryBot.define do
  factory :invoice_applied_tax, class: "Invoice::AppliedTax" do
    invoice
    tax
    tax_code { "vat-#{SecureRandom.uuid}" }
    tax_description { "French Standard VAT" }
    tax_name { "VAT" }
    tax_rate { 20.0 }
    amount_cents { 200 }
    amount_currency { "EUR" }
  end
end
