# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::WalletTransactionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:, credits_balance: 10, balance_cents: 1000) }
  let(:wallet_id) { wallet.id }

  before do
    subscription
    wallet
  end

  describe "POST /api/v1/wallet_transactions" do
    subject do
      post_with_token(
        organization,
        "/api/v1/wallet_transactions",
        {wallet_transaction: params}
      )
    end

    let(:params) do
      {
        wallet_id:,
        paid_credits: "10",
        granted_credits: "10",
        name: "Custom Top-up Name"
      }
    end

    include_examples "requires API permission", "wallet_transaction", "write"

    it "creates a wallet transactions" do
      subject

      expect(response).to have_http_status(:success)

      wallet_transactions = json[:wallet_transactions]

      expect(wallet_transactions.count).to eq(2)

      paid_transaction = wallet_transactions.first
      granted_transaction = wallet_transactions.second

      expect(paid_transaction[:lago_id]).to be_present
      expect(paid_transaction[:status]).to eq("pending")
      expect(granted_transaction[:status]).to eq("settled")
      expect(granted_transaction[:lago_id]).to be_present
      expect(wallet_transactions).to all(include(name: "Custom Top-up Name", lago_wallet_id: wallet.id))
    end

    context "when paid credits is below the wallet minimum" do
      it "returns an error" do
        wallet.update!(paid_top_up_min_amount_cents: 20_00)
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:paid_credits]).to eq(["amount_below_minimum"])
      end
    end

    context "with voided credits" do
      let(:wallet) { create(:wallet, customer:, credits_balance: 20, balance_cents: 2000) }
      let(:params) do
        {
          wallet_id:,
          voided_credits: "10"
        }
      end

      it "creates a wallet transactions" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:wallet_transactions].count).to eq(1)
        expect(json[:wallet_transactions].first).to include(
          lago_id: String,
          status: "settled",
          transaction_status: "voided",
          lago_wallet_id: wallet.id
        )
        expect(wallet.reload.credits_balance).to eq(10)
      end
    end

    context "when metadata is present" do
      let(:params) do
        {
          wallet_id:,
          paid_credits: "10",
          granted_credits: "10",
          voided_credits: "5",
          metadata: [{"key" => "valid_value", "value" => "also_valid"}]
        }
      end

      it "creates the wallet transactions with correct data" do
        subject

        expect(response).to have_http_status(:success)

        wallet_transactions = json[:wallet_transactions]

        expect(wallet_transactions.count).to eq(3)
        expect(wallet_transactions).to all(include(metadata: [{key: "valid_value", value: "also_valid"}]))
      end
    end

    context "when wallet does not exist" do
      let(:wallet_id) { "#{wallet.id}123" }

      it "returns unprocessable_entity error" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /api/v1/wallet_transactions" do
    subject do
      get_with_token(organization, "/api/v1/wallets/#{wallet_id}/wallet_transactions", params)
    end

    let(:params) { {} }
    let(:wallet_transaction_first) { create(:wallet_transaction, wallet:) }
    let(:wallet_transaction_second) { create(:wallet_transaction, wallet:) }
    let(:wallet_transaction_third) { create(:wallet_transaction) }

    before do
      wallet_transaction_first
      wallet_transaction_second
      wallet_transaction_third
    end

    include_examples "requires API permission", "wallet_transaction", "read"

    it "returns wallet transactions" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:wallet_transactions].count).to eq(2)
      expect(json[:wallet_transactions].first[:lago_id]).to eq(wallet_transaction_second.id)
      expect(json[:wallet_transactions].last[:lago_id]).to eq(wallet_transaction_first.id)
    end

    context "with pagination" do
      let(:params) { {page: 1, per_page: 1} }

      it "returns wallet transactions with correct meta data" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:wallet_transactions].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context "with status param" do
      let(:params) { {status: "pending"} }
      let(:wallet_transaction_second) { create(:wallet_transaction, wallet:, status: "pending") }

      it "returns wallet transactions with correct status" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transactions].count).to eq(1)
        expect(json[:wallet_transactions].first[:lago_id]).to eq(wallet_transaction_second.id)
      end
    end

    context "with transaction type param" do
      let(:params) { {transaction_type: "outbound"} }
      let(:wallet_transaction_second) { create(:wallet_transaction, wallet:, transaction_type: "outbound") }

      it "returns wallet transactions with correct transaction type" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transactions].count).to eq(1)
        expect(json[:wallet_transactions].first[:lago_id]).to eq(wallet_transaction_second.id)
      end
    end

    context "when wallet does not exist" do
      let(:wallet_id) { SecureRandom.uuid }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/v1/wallet_transactions/:id" do
    subject do
      get_with_token(organization, "/api/v1/wallet_transactions/#{wallet_transaction_id}", params)
    end

    let(:params) { {} }
    let(:wallet_transaction) { create(:wallet_transaction, wallet:) }
    let(:wallet_transaction_id) { wallet_transaction.id }

    include_examples "requires API permission", "wallet_transaction", "read"

    it "returns the wallet transaction" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:wallet_transaction][:lago_id]).to eq(wallet_transaction.id)
    end

    context "when wallet transaction belongs to another organization" do
      let(:customer) { create(:customer, organization: create(:organization)) }
      let(:subscription) { create(:subscription, customer:) }
      let(:wallet) { create(:wallet, customer:) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet:) }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when wallet_transaction does not exist" do
      let(:wallet_transaction_id) { SecureRandom.uuid }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/wallet_transactions/:id/payment_url" do
    subject do
      post_with_token(organization, "/api/v1/wallet_transactions/#{wallet_transaction_id}/payment_url")
    end

    context "when wallet transaction exits" do
      let(:wallet_transaction_id) { wallet_transaction.id }
      let(:wallet_transaction) { create(:wallet_transaction, :with_invoice, wallet:, status: :pending, customer:) }
      let(:wallet) { create(:wallet, customer:) }
      let(:customer) { create(:customer, :with_stripe_payment_provider, organization:) }
      let(:generated_payment_url) { "https://example.com" }

      before do
        allow(::Stripe::Checkout::Session).to receive(:create).and_return({"url" => generated_payment_url})
      end

      include_examples "requires API permission", "wallet_transaction", "write"

      it "returns the generated payment url" do
        subject

        expect(response).to have_http_status(:success)
        expect(json).to match({
          wallet_transaction_payment_details: hash_including(payment_url: generated_payment_url)
        })
      end
    end

    context "when wallet_transaction does not exist" do
      let(:wallet_transaction_id) { SecureRandom.uuid }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
