# frozen_string_literal: true

RSpec.shared_examples "a wallet index endpoint" do
  let!(:wallet) { create(:wallet, customer:) }
  let(:external_id) { customer.external_id }
  let(:params) { {page: 1, per_page: 1} }

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
end
