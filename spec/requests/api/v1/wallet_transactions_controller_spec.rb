# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::WalletTransactionsController do
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

      expect(wallet_transactions.first[:payment_method][:payment_method_type]).to eq("provider")
      expect(wallet_transactions.first[:payment_method][:payment_method_id]).to eq(nil)
      expect(wallet_transactions.second[:payment_method][:payment_method_type]).to eq("provider")
      expect(wallet_transactions.second[:payment_method][:payment_method_id]).to eq(nil)

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
      let(:wallet) { create(:wallet, :with_inbound_transaction, customer:, credits_balance: 20, balance_cents: 2000) }
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

    context "with a targeted voided transaction" do
      let(:wallet) { create(:wallet, customer:, credits_balance: 20, balance_cents: 2000) }
      let(:grant_a) do
        create(:wallet_transaction, wallet:, transaction_type: :inbound, transaction_status: :granted,
          status: :settled, amount: 5, credit_amount: 5, remaining_amount_cents: 500)
      end
      let(:grant_b) do
        create(:wallet_transaction, wallet:, transaction_type: :inbound, transaction_status: :granted,
          status: :settled, amount: 15, credit_amount: 15, remaining_amount_cents: 1500)
      end

      before do
        grant_a
        grant_b
      end

      # grant_a is created first at the same priority, so it is first in consumption order:
      # a pool-wide void would drain it before grant_b. Targeting grant_b therefore proves
      # the void was routed to the specified grant rather than falling back to FIFO.
      context "without an amount" do
        let(:params) { {wallet_id:, voided_transaction_id: grant_b.id} }

        it "voids the targeted grant's whole remaining and leaves the earlier grant untouched" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:wallet_transactions].count).to eq(1)
          expect(json[:wallet_transactions].first).to include(
            transaction_status: "voided",
            credit_amount: "15.0"
          )
          expect(grant_b.reload.remaining_amount_cents).to eq(0)
          expect(grant_a.reload.remaining_amount_cents).to eq(500)
          expect(wallet.reload.credits_balance).to eq(5)
        end
      end

      context "with an explicit amount" do
        let(:params) { {wallet_id:, voided_transaction_id: grant_b.id, voided_credits: "2"} }

        it "voids that amount from the targeted grant only" do
          subject

          expect(response).to have_http_status(:success)
          expect(grant_b.reload.remaining_amount_cents).to eq(1300)
          expect(grant_a.reload.remaining_amount_cents).to eq(500)
        end
      end

      context "when the amount exceeds the targeted grant remaining" do
        let(:params) { {wallet_id:, voided_transaction_id: grant_a.id, voided_credits: "10"} }

        it "returns an error without touching any grant" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:amount_cents]).to eq(["exceeds_remaining_transaction_amount"])
          expect(grant_a.reload.remaining_amount_cents).to eq(500)
        end
      end

      context "when the targeted transaction belongs to another wallet" do
        let(:other_grant) { create(:wallet_transaction, transaction_type: :inbound, remaining_amount_cents: 500) }
        let(:params) { {wallet_id:, voided_transaction_id: other_grant.id} }

        it "returns a not found error" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:voided_transaction_id]).to eq(["wallet_transaction_not_found"])
        end
      end

      context "when the targeted grant has no remaining balance" do
        let(:consumed_grant) do
          create(:wallet_transaction, wallet:, transaction_type: :inbound, transaction_status: :granted,
            status: :settled, amount: 5, credit_amount: 5, remaining_amount_cents: 0)
        end
        let(:params) { {wallet_id:, voided_transaction_id: consumed_grant.id} }

        it "returns an error" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:voided_transaction_id]).to eq(["no_remaining_amount"])
        end
      end

      context "when the wallet is not traceable" do
        let(:wallet) { create(:wallet, customer:, credits_balance: 20, balance_cents: 2000, traceable: false) }
        let(:params) { {wallet_id:, voided_transaction_id: grant_a.id} }

        it "rejects targeting" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:voided_transaction_id]).to eq(["wallet_not_traceable"])
        end
      end

      context "when voided_transaction_id is blank" do
        # An SDK may serialize an unset field as "" rather than omitting it: still a pool-wide void.
        let(:params) { {wallet_id:, voided_credits: "5", voided_transaction_id: ""} }

        it "falls back to a pool-wide void" do
          subject

          expect(response).to have_http_status(:success)
          expect(grant_a.reload.remaining_amount_cents).to eq(0)
          expect(grant_b.reload.remaining_amount_cents).to eq(1500)
        end
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

    context "when priority is present" do
      let(:params) do
        {
          wallet_id:,
          paid_credits: "10",
          granted_credits: "10",
          priority: 1
        }
      end

      it "creates the wallet transactions with correct priority" do
        subject

        expect(response).to have_http_status(:success)

        wallet_transactions = json[:wallet_transactions]

        expect(wallet_transactions.count).to eq(2)
        expect(wallet_transactions).to all(include(priority: 1))
      end
    end

    context "when wallet does not exist" do
      let(:wallet_id) { "#{wallet.id}123" }

      it "returns unprocessable_entity error" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with invoice_custom_section" do
      let(:params) do
        {
          wallet_id:,
          paid_credits: "10",
          name: "Custom Top-up Name",
          invoice_custom_section: {invoice_custom_section_codes: ["section_code_1"]}
        }
      end

      before do
        CurrentContext.source = "api"
        create(:invoice_custom_section, organization:, code: "section_code_1")
      end

      it "creates the wallet transactions with correct data" do
        subject

        expect(response).to have_http_status(:success)

        wallet_transaction = WalletTransaction.find(json[:wallet_transactions].first[:lago_id])
        expect(wallet_transaction.applied_invoice_custom_sections.count).to eq(1)
        expect(wallet_transaction.applied_invoice_custom_sections.first.invoice_custom_section.code).to eq("section_code_1")
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
      expect(json[:wallet_transactions].first[:billing_entity_code]).to eq(wallet.billing_entity.code)
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

    context "with transaction_status filter" do
      # Override outer context transactions to avoid interference
      let(:wallet_transaction_first) { nil }
      let(:wallet_transaction_second) { nil }

      let(:purchased_transaction) do
        create(:wallet_transaction, wallet:, transaction_status: :purchased)
      end
      let(:granted_transaction) do
        create(:wallet_transaction, wallet:, transaction_status: :granted)
      end
      let(:voided_transaction) do
        create(:wallet_transaction, wallet:, transaction_status: :voided)
      end
      let(:invoiced_transaction) do
        create(:wallet_transaction, wallet:, transaction_status: :invoiced)
      end

      before do
        purchased_transaction
        granted_transaction
        voided_transaction
        invoiced_transaction
      end

      context "with purchased status" do
        let(:params) { {transaction_status: "purchased"} }

        it "filters by purchased status" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:wallet_transactions].pluck(:lago_id)).to eq([purchased_transaction.id])
        end
      end

      context "with granted status" do
        let(:params) { {transaction_status: "granted"} }

        it "filters by granted status" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:wallet_transactions].pluck(:lago_id)).to eq([granted_transaction.id])
        end
      end

      context "with voided status" do
        let(:params) { {transaction_status: "voided"} }

        it "filters by voided status" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:wallet_transactions].pluck(:lago_id)).to eq([voided_transaction.id])
        end
      end

      context "with invoiced status" do
        let(:params) { {transaction_status: "invoiced"} }

        it "filters by invoiced status" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:wallet_transactions].pluck(:lago_id)).to eq([invoiced_transaction.id])
        end
      end

      context "with invalid transaction_status value" do
        let(:params) { {transaction_status: "invalid"} }

        it "ignores invalid transaction_status values" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:wallet_transactions].count).to eq(4)
        end
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

    context "with applied_invoice_custom_sections in response" do
      before { create(:wallet_transaction_applied_invoice_custom_section, wallet_transaction:) }

      it "includes applied_invoice_custom_sections in the serialized response" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transaction][:applied_invoice_custom_sections].count).to eq(1)
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

  describe "GET /api/v1/wallet_transactions/:id/consumptions" do
    subject { get_with_token(organization, "/api/v1/wallet_transactions/#{wallet_transaction.id}/consumptions", params) }

    let(:params) { {} }
    let(:wallet) { create(:wallet, customer:, traceable: true) }
    let(:wallet_transaction) { create(:wallet_transaction, wallet:, transaction_type: "inbound", remaining_amount_cents: 10000) }

    include_examples "requires API permission", "wallet_transaction", "read"

    context "with consumptions" do
      let(:consumption1) do
        create(:wallet_transaction_consumption,
          organization:,
          inbound_wallet_transaction: wallet_transaction,
          outbound_wallet_transaction: create(:wallet_transaction, wallet:, transaction_type: "outbound"),
          consumed_amount_cents: 500)
      end
      let(:consumption2) do
        create(:wallet_transaction_consumption,
          organization:,
          inbound_wallet_transaction: wallet_transaction,
          outbound_wallet_transaction: create(:wallet_transaction, wallet:, transaction_type: "outbound"),
          consumed_amount_cents: 300)
      end

      before do
        consumption1
        consumption2
      end

      it "returns paginated consumptions with nested outbound transaction" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transaction_consumptions].count).to eq(2)
        expect(json[:wallet_transaction_consumptions].first[:lago_id]).to eq(consumption2.id)
        expect(json[:wallet_transaction_consumptions].first[:amount_cents]).to eq(300)
        expect(json[:wallet_transaction_consumptions].first[:wallet_transaction]).to be_present
        expect(json[:wallet_transaction_consumptions].first[:wallet_transaction][:lago_id]).to eq(consumption2.outbound_wallet_transaction_id)
        expect(json[:meta]).to be_present
      end
    end

    context "with pagination" do
      let(:params) { {page: 1, per_page: 2} }

      before do
        3.times do
          create(:wallet_transaction_consumption,
            organization:,
            inbound_wallet_transaction: wallet_transaction,
            outbound_wallet_transaction: create(:wallet_transaction, wallet:, transaction_type: "outbound"))
        end
      end

      it "returns paginated results" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transaction_consumptions].count).to eq(2)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(3)
      end
    end

    context "when wallet is not traceable" do
      let(:wallet) { create(:wallet, customer:, traceable: false) }

      it "returns unprocessable_content error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to eq("validation_errors")
        expect(json[:error_details][:wallet]).to include("not_traceable")
      end
    end

    context "when transaction type is outbound" do
      let(:wallet_transaction) { create(:wallet_transaction, wallet:, transaction_type: "outbound") }

      it "returns unprocessable_content error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to eq("validation_errors")
        expect(json[:error_details][:transaction_type]).to include("invalid_transaction_type")
      end
    end

    context "when wallet_transaction does not exist" do
      let(:wallet_transaction) { build(:wallet_transaction, id: SecureRandom.uuid) }

      it "returns not_found error" do
        subject

        expect(response).to be_not_found_error("wallet_transaction")
      end
    end

    context "when wallet_transaction belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_customer) { create(:customer, organization: other_organization) }
      let(:other_wallet) { create(:wallet, customer: other_customer, traceable: true) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet: other_wallet, transaction_type: "inbound", remaining_amount_cents: 10000) }

      it "returns not_found error" do
        subject

        expect(response).to be_not_found_error("wallet_transaction")
      end
    end
  end

  describe "GET /api/v1/wallet_transactions/:id/fundings" do
    subject { get_with_token(organization, "/api/v1/wallet_transactions/#{wallet_transaction.id}/fundings", params) }

    let(:params) { {} }
    let(:wallet) { create(:wallet, customer:, traceable: true) }
    let(:wallet_transaction) { create(:wallet_transaction, wallet:, transaction_type: "outbound") }

    include_examples "requires API permission", "wallet_transaction", "read"

    context "with fundings" do
      let(:inbound_transaction1) { create(:wallet_transaction, wallet:, transaction_type: "inbound", remaining_amount_cents: 10000) }
      let(:inbound_transaction2) { create(:wallet_transaction, wallet:, transaction_type: "inbound", remaining_amount_cents: 10000) }
      let(:funding1) do
        create(:wallet_transaction_consumption,
          organization:,
          inbound_wallet_transaction: inbound_transaction1,
          outbound_wallet_transaction: wallet_transaction,
          consumed_amount_cents: 500)
      end
      let(:funding2) do
        create(:wallet_transaction_consumption,
          organization:,
          inbound_wallet_transaction: inbound_transaction2,
          outbound_wallet_transaction: wallet_transaction,
          consumed_amount_cents: 300)
      end

      before do
        funding1
        funding2
      end

      it "returns paginated fundings with nested inbound transaction" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transaction_fundings].count).to eq(2)
        expect(json[:wallet_transaction_fundings].first[:lago_id]).to eq(funding2.id)
        expect(json[:wallet_transaction_fundings].first[:amount_cents]).to eq(300)
        expect(json[:wallet_transaction_fundings].first[:wallet_transaction]).to be_present
        expect(json[:wallet_transaction_fundings].first[:wallet_transaction][:lago_id]).to eq(inbound_transaction2.id)
        expect(json[:meta]).to be_present
      end
    end

    context "with pagination" do
      let(:params) { {page: 1, per_page: 2} }

      before do
        3.times do
          inbound = create(:wallet_transaction, wallet:, transaction_type: "inbound", remaining_amount_cents: 10000)
          create(:wallet_transaction_consumption,
            organization:,
            inbound_wallet_transaction: inbound,
            outbound_wallet_transaction: wallet_transaction)
        end
      end

      it "returns paginated results" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transaction_fundings].count).to eq(2)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(3)
      end
    end

    context "when wallet is not traceable" do
      let(:wallet) { create(:wallet, customer:, traceable: false) }

      it "returns unprocessable_content error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to eq("validation_errors")
        expect(json[:error_details][:wallet]).to include("not_traceable")
      end
    end

    context "when transaction type is inbound" do
      let(:wallet_transaction) { create(:wallet_transaction, wallet:, transaction_type: "inbound", remaining_amount_cents: 10000) }

      it "returns unprocessable_content error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to eq("validation_errors")
        expect(json[:error_details][:transaction_type]).to include("invalid_transaction_type")
      end
    end

    context "when wallet_transaction does not exist" do
      let(:wallet_transaction) { build(:wallet_transaction, id: SecureRandom.uuid) }

      it "returns not_found error" do
        subject

        expect(response).to be_not_found_error("wallet_transaction")
      end
    end

    context "when wallet_transaction belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_customer) { create(:customer, organization: other_organization) }
      let(:other_wallet) { create(:wallet, customer: other_customer, traceable: true) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet: other_wallet, transaction_type: "outbound") }

      it "returns not_found error" do
        subject

        expect(response).to be_not_found_error("wallet_transaction")
      end
    end
  end
end
