# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::WalletsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }

  let(:external_id) { customer.external_id }

  describe "GET /api/v1/customers/:external_id/wallets" do
    subject do
      get_with_token(organization, "/api/v1/customers/#{external_id}/wallets", params)
    end

    let(:params) { {page: 1, per_page: 1} }

    let!(:wallet) { create(:wallet, customer:) }

    include_examples "requires API permission", "wallet", "read"

    it "returns wallets" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:wallets].count).to eq(1)
      expect(json[:wallets].first[:lago_id]).to eq(wallet.id)
      expect(json[:wallets].first[:name]).to eq(wallet.name)
      expect(json[:wallets].first[:recurring_transaction_rules]).to be_empty
      expect(json[:wallets].first[:applies_to]).to be_present
    end

    context "with pagination" do
      before { create(:wallet, customer:) }

      it "returns wallets with correct meta data" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:wallets].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context "when external_customer_id does not belong to the current organization" do
      let(:other_org_customer) { create(:customer) }
      let(:external_id) { other_org_customer.external_id }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
