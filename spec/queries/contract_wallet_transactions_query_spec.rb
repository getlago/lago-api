# frozen_string_literal: true

require "rails_helper"

describe ContractWalletTransactionsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:contract_wallet) { create(:catalog_wallet, organization:) }
  let_it_be(:other_contract_wallet) { create(:catalog_wallet, organization:) }
  let_it_be(:credit_allocation) do
    create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: contract_wallet, code: "monthly_allowance")
  end
  let_it_be(:top_up) do
    create(:catalog_wallet_transaction, organization:, catalog_wallet: contract_wallet, created_at: Time.zone.parse("2026-10-04 10:00:00"))
  end
  let_it_be(:pending_top_up) do
    create(:catalog_wallet_transaction, :pending, organization:, catalog_wallet: contract_wallet,
      created_at: Time.zone.parse("2026-10-03 10:00:00"))
  end
  let_it_be(:grant) do
    create(:catalog_wallet_transaction, :billing_cycle_grant, organization:, catalog_wallet: contract_wallet, credit_allocation:,
      created_at: Time.zone.parse("2026-10-02 10:00:00"))
  end
  let_it_be(:invoice_application) do
    create(:catalog_wallet_transaction, :invoice_application, organization:, catalog_wallet: contract_wallet,
      created_at: Time.zone.parse("2026-10-01 10:00:00"))
  end
  let_it_be(:other_wallet_top_up) do
    create(:catalog_wallet_transaction, organization:, catalog_wallet: other_contract_wallet,
      created_at: Time.zone.parse("2026-10-05 10:00:00"))
  end

  let(:pagination) { nil }
  let(:filters) { {} }

  before_all { create(:catalog_wallet_transaction, organization: create(:organization)) }

  it "returns the wallet transactions of the organization, the latest first" do
    expect(result).to be_success
    expect(result.wallet_transactions).to eq([other_wallet_top_up, top_up, pending_top_up, grant, invoice_application])
  end

  context "when filtering by contract_wallet_id" do
    let(:filters) { {contract_wallet_id: contract_wallet.id} }

    it "returns only the wallet's transactions" do
      expect(result.wallet_transactions).to eq([top_up, pending_top_up, grant, invoice_application])
    end
  end

  context "when filtering by direction" do
    let(:filters) { {direction: "outbound"} }

    it "returns the transactions in that direction" do
      expect(result.wallet_transactions).to eq([invoice_application])
    end

    context "when the direction is unknown" do
      let(:filters) { {direction: "sideways"} }

      it "fails on that filter with the directions allowed" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseQuery::FiltersFailure)
        expect(result.error.filters).to eq(direction: {allowed_values: %w[inbound outbound]})
      end
    end
  end

  context "when filtering by status" do
    let(:filters) { {status: "pending"} }

    it "returns the transactions in that status" do
      expect(result.wallet_transactions).to eq([pending_top_up])
    end

    context "when the status is unknown" do
      let(:filters) { {status: "expired"} }

      it "fails on that filter with the statuses allowed" do
        expect(result).not_to be_success
        expect(result.error.filters).to eq(status: {allowed_values: %w[pending settled failed]})
      end
    end

    context "when the status is a list" do
      let(:filters) { {status: %w[pending settled]} }

      it "fails on that filter" do
        expect(result).not_to be_success
        expect(result.error.filters).to eq(status: {})
      end
    end
  end

  context "when filtering by reason" do
    let(:filters) { {reason: "credit_allocation"} }

    it "returns the transactions with that reason" do
      expect(result.wallet_transactions).to eq([grant])
    end

    context "when the reason is unknown" do
      let(:filters) { {reason: "expiration"} }

      it "fails on that filter with the reasons allowed" do
        expect(result).not_to be_success
        expect(result.error.filters)
          .to eq(reason: {allowed_values: %w[top_up credit_allocation invoice_void invoice_application void]})
      end
    end
  end

  context "when filtering by credit_allocation_code" do
    let(:filters) { {contract_wallet_id: contract_wallet.id, credit_allocation_code: "monthly_allowance"} }

    it "returns the transactions that credit allocation created" do
      expect(result.wallet_transactions).to eq([grant])
    end

    context "when another wallet has a credit allocation with the same code" do
      let(:other_grant) do
        create(:catalog_wallet_transaction, :billing_cycle_grant, organization:, catalog_wallet: other_contract_wallet,
          credit_allocation: create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: other_contract_wallet,
            code: "monthly_allowance"))
      end

      before { other_grant }

      it "leaves its transactions out" do
        expect(result.wallet_transactions).to eq([grant])
      end
    end

    context "when the credit allocation was removed and its code reused" do
      let(:removed_credit_allocation) do
        create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: contract_wallet, code: "weekly_allowance",
          deleted_at: Time.current)
      end
      let(:removed_grant) do
        create(:catalog_wallet_transaction, :billing_cycle_grant, organization:, catalog_wallet: contract_wallet,
          credit_allocation: removed_credit_allocation, created_at: Time.zone.parse("2026-09-01 10:00:00"))
      end
      let(:new_grant) do
        create(:catalog_wallet_transaction, :billing_cycle_grant, organization:, catalog_wallet: contract_wallet,
          credit_allocation: create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: contract_wallet,
            code: "weekly_allowance"),
          created_at: Time.zone.parse("2026-09-02 10:00:00"))
      end
      let(:filters) { {contract_wallet_id: contract_wallet.id, credit_allocation_code: "weekly_allowance"} }

      before do
        removed_grant
        new_grant
      end

      it "returns the transactions of both" do
        expect(result.wallet_transactions).to eq([new_grant, removed_grant])
      end
    end

    context "when no credit allocation has the code" do
      let(:filters) { {contract_wallet_id: contract_wallet.id, credit_allocation_code: "unknown"} }

      it "returns nothing" do
        expect(result).to be_success
        expect(result.wallet_transactions).to eq([])
      end
    end

    context "when the code is not a string" do
      let(:filters) { {credit_allocation_code: {eq: "monthly_allowance"}} }

      it "fails on that filter" do
        expect(result).not_to be_success
        expect(result.error.filters).to eq(credit_allocation_code: {})
      end
    end
  end

  context "when filtering by created_at" do
    let(:filters) { {created_at_from: "2026-10-02", created_at_to: "2026-10-03T10:00:00Z"} }

    it "returns the transactions created in the range, bounds included" do
      expect(result.wallet_transactions).to eq([pending_top_up, grant])
    end

    context "when a bound is not a date" do
      let(:filters) { {created_at_from: "2026-13-01"} }

      it "fails on that filter" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({created_at_from: ["invalid_date"]})
      end
    end
  end

  context "with cursor pagination" do
    let(:pagination) { CursorPagination::Cursor.new(table: "catalog_wallet_transactions", limit: 2) }

    it "returns a page of that size, with a cursor to the next one" do
      page = CursorPagination::Page.new(records: result.wallet_transactions, cursor: pagination)

      expect(page.records).to eq([other_wallet_top_up, top_up])
      expect(page.meta[:next_cursor]).to be_present
    end
  end
end
