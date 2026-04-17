# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::WalletCredits::AddService do
  subject(:service) { described_class.new(quote:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }

  describe "#call" do
    let(:result) { service.call }

    context "with valid params" do
      let(:params) do
        {
          name: "Monthly credits",
          currency: "EUR",
          rate_amount: "1.0",
          paid_credits: "500.0",
          granted_credits: "500.0",
          position: 1
        }
      end

      it "appends the wallet credit and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["wallet_credits"].length).to eq(1)
        expect(result.quote.billing_items["wallet_credits"].first["name"]).to eq("Monthly credits")
      end

      it "generates a stable id with qtw_ prefix" do
        expect(result.quote.billing_items["wallet_credits"].first["id"]).to start_with("qtw_")
      end
    end

    context "with recurring_transaction_rules" do
      let(:params) do
        {
          name: "Credits",
          currency: "EUR",
          rate_amount: "1.0",
          paid_credits: "500.0",
          granted_credits: "500.0",
          recurring_transaction_rules: [
            {trigger: "interval", interval: "monthly", paid_credits: "500.0", granted_credits: "500.0"}
          ]
        }
      end

      it "generates ids for nested recurring rules" do
        rules = result.quote.billing_items["wallet_credits"].first["recurring_transaction_rules"]
        expect(rules.first["id"]).to start_with("qtrr_")
      end

      it "preserves existing rule ids" do
        params[:recurring_transaction_rules].first[:id] = "qtrr_existing"
        rules = result.quote.billing_items["wallet_credits"].first["recurring_transaction_rules"]
        expect(rules.first["id"]).to eq("qtrr_existing")
      end
    end

    context "when quote is nil" do
      let(:params) { {name: "Credits", currency: "EUR", rate_amount: "1.0", paid_credits: "500.0", granted_credits: "500.0"} }

      it "returns not_found_failure" do
        result = described_class.new(quote: nil, params:).call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "when quote is not draft" do
      let(:params) { {name: "Credits", currency: "EUR", rate_amount: "1.0", paid_credits: "500.0", granted_credits: "500.0"} }

      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when order type is one_off" do
      let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
      let(:params) { {name: "Credits", currency: "EUR", rate_amount: "1.0", paid_credits: "500.0", granted_credits: "500.0"} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("wallet_credits not allowed for one_off order type")
      end
    end
  end
end
