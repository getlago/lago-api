# frozen_string_literal: true

require "rails_helper"

describe Api::V2::ContractWallets::TransactionsController do
  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { %w[product_catalog catalog_wallets] }
  let(:customer) { create(:customer, organization:, external_id: "acme", currency: "USD") }
  let(:contract) { create(:contract, organization:, customer:, external_id: "acme-pro") }
  let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "ai_credits", currency: "USD") }
  let(:wallet_transaction) do
    create(:catalog_wallet_transaction, organization:, catalog_wallet: contract_wallet, purchase_amount_cents: 5000,
      credit_amount_cents: 10_000, remaining_credit_amount_cents: 7500, priority: 10, created_at: Time.zone.parse("2026-10-03 10:00:00"))
  end
  let(:external_id) { contract.external_id }
  let(:wallet_code) { contract_wallet.code }
  let(:keys) do
    %i[
      lago_id lago_wallet_id wallet_code lago_invoice_id lago_credit_allocation_id credit_allocation_code direction status reason
      allocation_type currency purchase_amount_cents credit_amount_cents remaining_credit_amount_cents priority settled_at failed_at
      created_at updated_at
    ]
  end

  shared_examples "requires the catalog_wallets flag" do
    context "when the organization is not on catalog wallets" do
      let(:feature_flags) { %w[product_catalog] }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end
  end

  shared_examples "requires the contract wallet" do
    context "when the wallet does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when the wallet belongs to another contract" do
      let(:wallet_code) { create(:catalog_wallet, organization:, code: "other").code }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when the wallet is deleted" do
      let(:contract_wallet) do
        create(:catalog_wallet, organization:, customer:, contract:, code: "ai_credits", currency: "USD", deleted_at: Time.current)
      end

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when the contract does not exist" do
      let(:external_id) { "unknown" }

      it "returns a not found error on the wallet" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when the contract belongs to another organization" do
      let(:contract) { create(:contract, organization: create(:organization), external_id: "acme-pro") }
      let(:contract_wallet) { create(:catalog_wallet, organization: contract.organization, contract:, code: "ai_credits") }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when an ended contract reuses the external id" do
      let(:ended_contract) do
        create(:contract, :terminated, organization:, customer:, external_id: "acme-pro", started_at: 2.months.ago)
      end

      before { ended_contract }

      it "asks for the contract code" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "contract_code", meta: {}}])
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id/wallets/:wallet_code/transactions" do
    subject { get_with_token(organization, "/api/v2/contracts/#{external_id}/wallets/#{wallet_code}/transactions", query) }

    let(:query) { {} }
    let(:credit_allocation) do
      create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: contract_wallet, code: "monthly_allowance")
    end
    let(:pending_top_up) do
      create(:catalog_wallet_transaction, :pending, organization:, catalog_wallet: contract_wallet,
        created_at: Time.zone.parse("2026-10-02 10:00:00"))
    end
    let(:grant) do
      create(:catalog_wallet_transaction, :billing_cycle_grant, organization:, catalog_wallet: contract_wallet, credit_allocation:,
        created_at: Time.zone.parse("2026-10-01 10:00:00"))
    end
    let(:invoice_application) do
      create(:catalog_wallet_transaction, :invoice_application, organization:, catalog_wallet: contract_wallet,
        invoice: create(:invoice, organization:, customer:), created_at: Time.zone.parse("2026-09-30 10:00:00"))
    end

    before do
      wallet_transaction
      pending_top_up
      grant
      invoice_application
      create(:catalog_wallet_transaction, organization:, catalog_wallet: create(:catalog_wallet, organization:, customer:, contract:))
    end

    include_examples "requires API permission", "wallet_transaction", "read"
    include_examples "requires the catalog_wallets flag"
    include_examples "requires the contract wallet"

    it "returns the wallet's transactions only, the latest first" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:wallet_transactions].map { it[:lago_id] })
        .to eq([wallet_transaction.id, pending_top_up.id, grant.id, invoice_application.id])
      expect(json[:wallet_transactions].map(&:keys)).to all(eq(keys))
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    it "renders null purchase and remaining amounts on the outbound ones" do
      subject

      expect(json[:wallet_transactions].map { it.slice(:direction, :reason, :allocation_type, :purchase_amount_cents, :remaining_credit_amount_cents) })
        .to eq([
          {direction: "inbound", reason: "top_up", allocation_type: nil, purchase_amount_cents: 5000, remaining_credit_amount_cents: 7500},
          {direction: "inbound", reason: "top_up", allocation_type: nil, purchase_amount_cents: 0, remaining_credit_amount_cents: 10_000},
          {direction: "inbound", reason: "credit_allocation", allocation_type: "billing_cycle", purchase_amount_cents: 0, remaining_credit_amount_cents: 10_000},
          {direction: "outbound", reason: "invoice_application", allocation_type: nil, purchase_amount_cents: nil, remaining_credit_amount_cents: nil}
        ])
    end

    context "when many transactions come from credit allocations", :bullet do
      before do
        create(:catalog_wallet_transaction, :billing_cycle_grant, organization:, catalog_wallet: contract_wallet,
          credit_allocation: create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: contract_wallet, code: "weekly_allowance"))
      end

      it "renders them without a query per transaction" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transactions].filter_map { it[:credit_allocation_code] }).to match_array(%w[monthly_allowance weekly_allowance])
      end
    end

    context "with the direction filter" do
      let(:query) { {direction: "outbound"} }

      it "returns the transactions in that direction" do
        subject

        expect(json[:wallet_transactions].map { it[:lago_id] }).to eq([invoice_application.id])
      end
    end

    context "with the status filter" do
      let(:query) { {status: "pending"} }

      it "returns the transactions in that status" do
        subject

        expect(json[:wallet_transactions].map { it[:lago_id] }).to eq([pending_top_up.id])
      end
    end

    context "with the reason filter" do
      let(:query) { {reason: "top_up"} }

      it "returns the transactions with that reason" do
        subject

        expect(json[:wallet_transactions].map { it[:lago_id] }).to eq([wallet_transaction.id, pending_top_up.id])
      end
    end

    context "with the credit_allocation_code filter" do
      let(:query) { {credit_allocation_code: "monthly_allowance"} }

      it "returns the transactions that credit allocation created" do
        subject

        expect(json[:wallet_transactions].map { it[:lago_id] }).to eq([grant.id])
      end
    end

    context "with several filters" do
      let(:query) { {direction: "inbound", status: "settled", reason: "credit_allocation"} }

      it "returns the transactions matching all of them" do
        subject

        expect(json[:wallet_transactions].map { it[:lago_id] }).to eq([grant.id])
      end
    end

    context "with an unknown status" do
      let(:query) { {status: "expired"} }

      it "returns a validation error with the statuses allowed" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "value_is_invalid", field: "status", meta: {allowed_values: %w[pending settled failed]}}]
        )
      end
    end

    context "with a list of reasons" do
      let(:query) { {reason: %w[top_up void]} }

      it "returns a validation error, rather than ignoring the filter" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "reason", meta: {}}])
      end
    end

    context "with an expansion" do
      let(:query) { {expands: %w[invoice]} }

      it "returns an invalid request error" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "when the wallet code contains a dot" do
      let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "ai.credits", currency: "USD") }

      it "returns its transactions" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transactions].map { it[:wallet_code] }.uniq).to eq(["ai.credits"])
      end
    end

    context "when the contract has ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "acme-pro") }

      it "returns the wallet's transactions" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transactions].size).to eq(4)
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :wallet_transactions, model: CatalogWalletTransaction do
      let(:paginated_path) { "/api/v2/contracts/#{contract.external_id}/wallets/#{contract_wallet.code}/transactions" }
      let(:create_paginated_record) do
        ->(created_at) { create(:catalog_wallet_transaction, organization:, catalog_wallet: contract_wallet, created_at:) }
      end
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :wallet_transactions do
      let(:filtered_path) { "/api/v2/contracts/#{contract.external_id}/wallets/#{contract_wallet.code}/transactions" }
      let(:create_filtered_record) do
        ->(created_at) { create(:catalog_wallet_transaction, organization:, catalog_wallet: contract_wallet, created_at:) }
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id/wallets/:wallet_code/transactions/:id" do
    subject { get_with_token(organization, "/api/v2/contracts/#{external_id}/wallets/#{wallet_code}/transactions/#{id}", query) }

    let(:id) { wallet_transaction.id }
    let(:query) { {} }

    before { contract_wallet }

    include_examples "requires API permission", "wallet_transaction", "read"
    include_examples "requires the catalog_wallets flag"
    include_examples "requires the contract wallet"

    it "returns the transaction" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:wallet_transaction]).to eq(
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
        settled_at: wallet_transaction.settled_at.iso8601(6),
        failed_at: nil,
        created_at: "2026-10-03T10:00:00.000000Z",
        updated_at: wallet_transaction.updated_at.iso8601(6)
      )
    end

    context "when the transaction is outbound" do
      let(:invoice) { create(:invoice, organization:, customer:) }
      let(:wallet_transaction) do
        create(:catalog_wallet_transaction, :invoice_application, organization:, catalog_wallet: contract_wallet, invoice:,
          credit_amount_cents: 2500)
      end

      it "returns it with the invoice it paid and null purchase and remaining amounts" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transaction]).to include(
          lago_invoice_id: invoice.id, direction: "outbound", status: "settled", reason: "invoice_application", allocation_type: nil,
          purchase_amount_cents: nil, credit_amount_cents: 2500, remaining_credit_amount_cents: nil
        )
      end
    end

    context "when it does not exist" do
      let(:id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("wallet_transaction")
      end
    end

    context "when the id is not a uuid" do
      let(:id) { "latest" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("wallet_transaction")
      end
    end

    context "when it belongs to another wallet of the contract" do
      let(:id) do
        create(:catalog_wallet_transaction, organization:, catalog_wallet: create(:catalog_wallet, organization:, customer:, contract:)).id
      end

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("wallet_transaction")
      end
    end

    context "with an expansion" do
      let(:query) { {expands: %w[invoice]} }

      it "returns an invalid request error" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "when the contract has ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "acme-pro") }

      it "returns the transaction" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transaction][:lago_id]).to eq(wallet_transaction.id)
      end
    end
  end
end
