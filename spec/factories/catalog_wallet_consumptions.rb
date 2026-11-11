# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_wallet_consumption do
    organization
    inbound_transaction { association(:catalog_wallet_transaction, organization:) }
    outbound_transaction do
      association(:catalog_wallet_transaction, :invoice_application, organization:, catalog_wallet: inbound_transaction.catalog_wallet)
    end
    fee { association(:fee, organization:, invoice: outbound_transaction.invoice) }
    credit_amount_cents { 1_000 }
  end
end
