# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::WalletCredits::UpdateService, type: :service do
  subject(:result) { described_class.call(quote_version:, id:, params:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:item_id) { "qtw_#{SecureRandom.uuid}" }
  let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation) }
  let(:quote_version) { quote.current_version }
  let(:id) { item_id }
  let(:params) { {paid_credits: "200.0"} }

  before do
    allow(License).to receive(:premium?).and_return(true)
    quote_version.update!(billing_items: {
      "wallet_credits" => [{"id" => item_id, "paid_credits" => "100.0"}]
    })
  end

  it "updates the wallet credit billing item" do
    expect(result).to be_success
    expect(result.quote_version.billing_items["wallet_credits"].first["paid_credits"]).to eq("200.0")
  end

  context "when not premium" do
    before { allow(License).to receive(:premium?).and_return(false) }

    it "returns forbidden failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "when quote_version is nil" do
    let(:quote_version) { nil }

    it "returns not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when quote_version is not draft" do
    let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation, version_trait: :approved) }

    it "returns not allowed failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotAllowedFailure)
    end
  end

  context "when item id is not found" do
    let(:id) { "qtw_nonexistent" }

    it "returns not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when updating recurring_transaction_rules" do
    let(:params) { {recurring_transaction_rules: [{"trigger" => "interval"}]} }

    it "normalizes rules with generated ids" do
      expect(result).to be_success
      rules = result.quote_version.billing_items["wallet_credits"].first["recurring_transaction_rules"]
      expect(rules.first["id"]).to start_with("qtrr_")
    end
  end
end
