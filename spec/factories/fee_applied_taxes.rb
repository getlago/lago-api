# frozen_string_literal: true

FactoryBot.define do
  factory :fee_applied_tax, class: "Fee::AppliedTax" do
    fee
    tax
    tax_code { "vat-#{SecureRandom.uuid}" }
    tax_description { "French Standard VAT" }
    tax_name { "VAT" }
    tax_rate { 20.0 }
    amount_cents { 200 }
    amount_currency { "EUR" }
  end
end
