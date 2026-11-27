# frozen_string_literal: true

require "rails_helper"

describe V2::ContractWalletTransactionSerializer do
  subject(:payload) { described_class.new(loaded_wallet_transaction, options).serialize }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, currency: "USD") }
  let_it_be(:contract) { create(:contract, organization:, customer:) }
  let_it_be(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "ai_credits", currency: "USD") }

  let(:wallet_transaction) do
    create(:catalog_wallet_transaction, organization:, catalog_wallet: contract_wallet, purchase_amount_cents: 5000,
      credit_amount_cents: 10_000, remaining_credit_amount_cents: 7500, priority: 10,
      settled_at: Time.zone.parse("2026-09-30 08:30:00"))
  end
  let(:loaded_wallet_transaction) { CatalogWalletTransaction.preload(described_class::PRELOADS).find(wallet_transaction.id) }
  let(:options) { {} }
  let(:top_up_payload) do
    {
      lago_id: wallet_transaction.id,
      lago_wallet_id: contract_wallet.id,
      wallet_code: "ai_credits",
      lago_invoice_id: nil,
      lago_credit_allocation_id: nil,
      credit_allocation_code: nil,
      direction: "inbound",
      status: "settled",
      reason: "top_up",
      allocation_type: nil,
      currency: "USD",
      purchase_amount_cents: 5000,
      credit_amount_cents: 10_000,
      remaining_credit_amount_cents: 7500,
      priority: 10,
      settled_at: "2026-09-30T08:30:00Z",
      failed_at: nil,
      created_at: wallet_transaction.created_at.iso8601,
      updated_at: wallet_transaction.updated_at.iso8601
    }
  end

  it "serializes a top-up with its purchase price apart from its credit" do
    expect(payload).to eq(top_up_payload)
  end

  context "when the top-up waits for its payment" do
    let(:invoice) { create(:invoice, organization:, customer:) }
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :pending, organization:, catalog_wallet: contract_wallet, invoice:,
        purchase_amount_cents: 5000, credit_amount_cents: 10_000, priority: 10)
    end

    it "renders it pending, with its purchase invoice" do
      expect(payload).to eq(
        top_up_payload.merge(lago_invoice_id: invoice.id, status: "pending", remaining_credit_amount_cents: 10_000, settled_at: nil)
      )
    end
  end

  context "when the top-up failed" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :failed, organization:, catalog_wallet: contract_wallet, purchase_amount_cents: 5000,
        credit_amount_cents: 10_000, priority: 10, failed_at: Time.zone.parse("2026-10-01 09:00:00"))
    end

    it "renders it failed, with the time it failed" do
      expect(payload).to eq(
        top_up_payload.merge(status: "failed", remaining_credit_amount_cents: 10_000, settled_at: nil, failed_at: "2026-10-01T09:00:00Z")
      )
    end
  end

  context "when a credit allocation created it" do
    let(:credit_allocation) do
      create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: contract_wallet, code: "monthly_allowance", deleted_at:)
    end
    let(:deleted_at) { nil }
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :billing_cycle_grant, organization:, catalog_wallet: contract_wallet, credit_allocation:,
        credit_amount_cents: 10_000, remaining_credit_amount_cents: 7500, priority: 10,
        settled_at: Time.zone.parse("2026-09-30 08:30:00"))
    end
    let(:grant_payload) do
      top_up_payload.merge(
        lago_credit_allocation_id: credit_allocation.id,
        credit_allocation_code: "monthly_allowance",
        reason: "credit_allocation",
        allocation_type: "billing_cycle",
        purchase_amount_cents: 0
      )
    end

    it "renders the credit allocation and its type" do
      expect(payload).to eq(grant_payload)
    end

    context "when the credit allocation was removed" do
      let(:deleted_at) { Time.current }

      it "still renders it" do
        expect(payload).to eq(grant_payload)
      end
    end
  end

  context "when it is outbound" do
    let(:invoice) { create(:invoice, organization:, customer:) }
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :invoice_application, organization:, catalog_wallet: contract_wallet, invoice:,
        credit_amount_cents: 2500, settled_at: Time.zone.parse("2026-09-30 08:30:00"))
    end

    it "renders null purchase and remaining amounts and priority, with the invoice it paid" do
      expect(payload).to eq(
        top_up_payload.merge(
          lago_invoice_id: invoice.id,
          direction: "outbound",
          reason: "invoice_application",
          purchase_amount_cents: nil,
          credit_amount_cents: 2500,
          remaining_credit_amount_cents: nil,
          priority: nil
        )
      )
    end
  end

  context "when the wallet was deleted" do
    let(:contract_wallet) do
      create(:catalog_wallet, organization:, customer:, contract:, code: "old_credits", currency: "USD", deleted_at: Time.current)
    end

    it "still renders the wallet" do
      expect(payload).to eq(top_up_payload.merge(wallet_code: "old_credits"))
    end
  end

  context "with microsecond timestamps" do
    let(:options) { {includes: %i[usec_timestamps]} }

    it "renders the datetimes to the microsecond" do
      expect(payload).to include(
        settled_at: "2026-09-30T08:30:00.000000Z",
        created_at: wallet_transaction.created_at.iso8601(6),
        updated_at: wallet_transaction.updated_at.iso8601(6)
      )
    end
  end
end
