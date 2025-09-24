# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::WalletSerializer do
  subject(:serializer) { described_class.new(wallet, root_name: "wallet", includes: %i[limitations recurring_transaction_rules]) }

  let(:wallet) { create(:wallet, :with_top_up_limits, allowed_fee_types: %w[charge]) }
  let(:recurring_transaction_rule) { create(:recurring_transaction_rule, wallet:) }
  let(:wallet_target) { create(:wallet_target, wallet:) }

  before do
    recurring_transaction_rule
    wallet_target
  end

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    expect(result["wallet"]).to include(
      "lago_id" => wallet.id,
      "lago_customer_id" => wallet.customer_id,
      "external_customer_id" => wallet.customer.external_id,
      "status" => wallet.status,
      "currency" => wallet.currency,
      "name" => wallet.name,
      "priority" => wallet.priority,
      "rate_amount" => wallet.rate_amount.to_s,
      "created_at" => wallet.created_at.iso8601,
      "expiration_at" => wallet.expiration_at&.iso8601,
      "last_balance_sync_at" => wallet.last_balance_sync_at&.iso8601,
      "last_consumed_credit_at" => wallet.last_consumed_credit_at&.iso8601,
      "terminated_at" => wallet.terminated_at,
      "credits_balance" => wallet.credits_balance.to_s,
      "balance_cents" => wallet.balance_cents,
      "credits_ongoing_balance" => wallet.credits_ongoing_balance.to_s,
      "credits_ongoing_usage_balance" => wallet.credits_ongoing_usage_balance.to_s,
      "ongoing_balance_cents" => wallet.ongoing_balance_cents,
      "ongoing_usage_balance_cents" => wallet.ongoing_usage_balance_cents,
      "consumed_credits" => wallet.consumed_credits.to_s,
      "invoice_requires_successful_payment" => wallet.invoice_requires_successful_payment,
      "paid_top_up_min_amount_cents" => wallet.paid_top_up_min_amount_cents,
      "paid_top_up_max_amount_cents" => wallet.paid_top_up_max_amount_cents
    )
    expect(result["wallet"]["applies_to"]["fee_types"]).to eq(%w[charge])
    expect(result["wallet"]["applies_to"]["billable_metric_codes"]).to eq([wallet_target.billable_metric.code])
    expect(result["wallet"]["recurring_transaction_rules"].first["lago_id"]).to eq(recurring_transaction_rule.id)
  end
end
