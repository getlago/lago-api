# frozen_string_literal: true

require "rails_helper"

describe ContractWalletsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:contract) { create(:contract, organization:) }
  let_it_be(:contract_wallet) { create(:catalog_wallet, organization:, contract:, created_at: Time.zone.parse("2026-10-03 10:00:00")) }
  let_it_be(:older_contract_wallet) { create(:catalog_wallet, organization:, contract:, created_at: Time.zone.parse("2026-10-01 10:00:00")) }
  let_it_be(:other_contract_wallet) { create(:catalog_wallet, organization:, created_at: Time.zone.parse("2026-10-02 10:00:00")) }

  let(:pagination) { nil }
  let(:filters) { {} }

  before_all do
    create(:catalog_wallet, organization:, contract:, deleted_at: Time.current)
    create(:catalog_wallet, organization: create(:organization))
  end

  it "returns the kept contract wallets of the organization, the latest first" do
    expect(result).to be_success
    expect(result.contract_wallets).to eq([contract_wallet, other_contract_wallet, older_contract_wallet])
  end

  context "when filtering by contract_id" do
    let(:filters) { {contract_id: contract.id} }

    it "returns only the contract's wallets" do
      expect(result.contract_wallets).to eq([contract_wallet, older_contract_wallet])
    end
  end

  context "when filtering by created_at" do
    let(:filters) { {created_at_from: "2026-10-02", created_at_to: "2026-10-03T10:00:00Z"} }

    it "returns the contract wallets created in the range, bounds included" do
      expect(result.contract_wallets).to eq([contract_wallet, other_contract_wallet])
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
    let(:pagination) { CursorPagination::Cursor.new(table: "catalog_wallets", limit: 2) }

    it "returns a page of that size, with a cursor to the next one" do
      page = CursorPagination::Page.new(records: result.contract_wallets, cursor: pagination)

      expect(page.records).to eq([contract_wallet, other_contract_wallet])
      expect(page.meta[:next_cursor]).to be_present
    end
  end
end
