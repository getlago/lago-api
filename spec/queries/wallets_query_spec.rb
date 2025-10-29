# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletsQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:)
  end

  let(:returned_ids) { result.wallets.pluck(:id) }
  let(:organization) { create :organization }
  let(:customer_1) { create :customer, organization:, external_id: "customer_1" }
  let(:customer_2) { create :customer, organization:, external_id: "customer_2" }
  let(:wallet_1) { create :wallet, customer: customer_1 }
  let(:wallet_2) { create :wallet, customer: customer_1 }
  let(:wallet_3) { create :wallet, customer: customer_2 }
  let(:wallet_4) { create :wallet }
  let(:pagination) { {page: 1, limit: 10} }
  let(:filters) { nil }

  before do
    wallet_1
    wallet_2
    wallet_3
    wallet_4
  end

  it "returns all wallets" do
    expect(result.wallets.count).to eq(3)
    expect(returned_ids).to include(wallet_1.id)
    expect(returned_ids).to include(wallet_2.id)
    expect(returned_ids).to include(wallet_3.id)
    expect(returned_ids).not_to include(wallet_4.id)
  end

  context "when wallets have the same values for the ordering criteria" do
    let(:wallet_2) do
      create(
        :wallet,
        customer: customer_1,
        id: "00000000-0000-0000-0000-000000000000",
        created_at: wallet_1.created_at
      )
    end

    it "returns a consistent list" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(3)
      expect(returned_ids).to include(wallet_1.id)
      expect(returned_ids).to include(wallet_2.id)
      expect(returned_ids.index(wallet_1.id)).to be > returned_ids.index(wallet_2.id)
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 2} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.wallets.count).to eq(1)
      expect(result.wallets.current_page).to eq(2)
      expect(result.wallets.prev_page).to eq(1)
      expect(result.wallets.next_page).to be_nil
      expect(result.wallets.total_pages).to eq(2)
      expect(result.wallets.total_count).to eq(3)
    end
  end

  context "when filtering by external_customer_id" do
    let(:filters) { {external_customer_id: customer_1.external_id} }

    it "returns only two wallets" do
      expect(result.wallets.count).to eq(2)
      expect(returned_ids).to include(wallet_1.id)
      expect(returned_ids).to include(wallet_2.id)
      expect(returned_ids).not_to include(wallet_3.id)
      expect(returned_ids).not_to include(wallet_4.id)
    end

    context "when customer is not found" do
      let(:filters) { {external_customer_id: "not_found_external_id"} }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("customer_not_found")
      end
    end
  end
end
