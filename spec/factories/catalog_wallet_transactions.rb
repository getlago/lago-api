# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_wallet_transaction do
    organization
    catalog_wallet { association(:catalog_wallet, organization:) }
    direction { "inbound" }
    status { "settled" }
    reason { "top_up" }
    purchase_amount_cents { 0 }
    credit_amount_cents { 10_000 }
    remaining_credit_amount_cents { credit_amount_cents }
    settled_at { Time.current }

    trait :pending do
      status { "pending" }
      settled_at { nil }
    end

    trait :billing_cycle_grant do
      reason { "credit_allocation" }
      allocation_type { "billing_cycle" }
      credit_allocation { association(:catalog_wallet_credit_allocation, organization:, catalog_wallet:) }
      source_cycle_started_at { Time.current.beginning_of_month }
    end

    trait :invoice_application do
      direction { "outbound" }
      reason { "invoice_application" }
      purchase_amount_cents { nil }
      remaining_credit_amount_cents { nil }
      invoice { association(:invoice, organization:) }
    end
  end
end
