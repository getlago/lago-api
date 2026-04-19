# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::WalletCredits::UpdateService, :premium do
  subject(:service) { described_class.new(quote:, id:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:item_id) { "qtw_existing" }
  let(:quote) do
    create(:quote, organization:, customer:, order_type: :subscription_creation,
      billing_items: {
        "wallet_credits" => [{
          "id" => item_id,
          "name" => "Monthly credits",
          "currency" => "EUR",
          "rate_amount" => "1.0",
          "paid_credits" => "500.0",
          "granted_credits" => "500.0",
          "recurring_transaction_rules" => [{"id" => "qtrr_existing", "trigger" => "interval"}]
        }]
      })
  end

  describe "#call" do
    let(:result) { service.call }
    let(:id) { item_id }

    context "with valid params" do
      let(:params) { {name: "Updated credits", paid_credits: "1000.0"} }

      it "updates the wallet credit fields and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["wallet_credits"].first["name"]).to eq("Updated credits")
        expect(result.quote.billing_items["wallet_credits"].first["paid_credits"]).to eq("1000.0")
      end

      it "preserves the existing id" do
        expect(result.quote.billing_items["wallet_credits"].first["id"]).to eq(item_id)
      end

      it "preserves existing recurring_transaction_rules when not included in params" do
        rules = result.quote.billing_items["wallet_credits"].first["recurring_transaction_rules"]
        expect(rules.first["id"]).to eq("qtrr_existing")
      end
    end

    context "when recurring_transaction_rules are updated" do
      let(:params) do
        {
          recurring_transaction_rules: [
            {trigger: "interval", interval: "monthly", paid_credits: "500.0"}
          ]
        }
      end

      it "generates ids for new rules" do
        rules = result.quote.billing_items["wallet_credits"].first["recurring_transaction_rules"]
        expect(rules.first["id"]).to start_with("qtrr_")
      end
    end

    context "when quote is nil" do
      let(:id) { item_id }
      let(:params) { {name: "Updated"} }

      it "returns not_found_failure" do
        result = described_class.new(quote: nil, id:, params:).call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "when quote is not draft" do
      let(:params) { {name: "Updated"} }

      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when item id is not found" do
      let(:id) { "qtw_nonexistent" }
      let(:params) { {name: "Updated"} }

      it "returns not_found_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("billing_item")
      end
    end
  end
end
