# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::WalletCredits::AddService, type: :service do
  subject(:result) { described_class.call(quote_version:, params:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation) }
  let(:quote_version) { quote.current_version }
  let(:params) { {paid_credits: "100.0"} }

  before { allow(License).to receive(:premium?).and_return(true) }

  it "adds the wallet credit to billing_items and returns the quote_version" do
    expect(result).to be_success
    expect(result.quote_version.billing_items["wallet_credits"].length).to eq(1)
    expect(result.quote_version.billing_items["wallet_credits"].first["paid_credits"]).to eq("100.0")
    expect(result.quote_version.billing_items["wallet_credits"].first["id"]).to start_with("qtw_")
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

  context "when order_forms feature flag is disabled" do
    let(:organization) { create(:organization) }

    it "returns forbidden failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "when quote_version is not draft" do
    let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation, version_trait: :approved) }

    it "returns not allowed failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotAllowedFailure)
    end
  end

  context "when order_type is one_off" do
    let(:quote) { create(:quote, :with_version, organization:, order_type: :one_off) }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "with recurring_transaction_rules" do
    let(:params) { {paid_credits: "100.0", recurring_transaction_rules: [{"trigger" => "interval", "interval" => "monthly"}]} }

    it "normalizes recurring rules with generated ids" do
      expect(result).to be_success
      rules = result.quote_version.billing_items["wallet_credits"].first["recurring_transaction_rules"]
      expect(rules.first["id"]).to start_with("qtrr_")
      expect(rules.first["trigger"]).to eq("interval")
    end
  end

  context "when recurring rule already has an id" do
    let(:existing_rule_id) { "qtrr_existing" }
    let(:params) { {paid_credits: "100.0", recurring_transaction_rules: [{"id" => existing_rule_id, "trigger" => "interval"}]} }

    it "preserves existing rule id" do
      expect(result).to be_success
      rules = result.quote_version.billing_items["wallet_credits"].first["recurring_transaction_rules"]
      expect(rules.first["id"]).to eq(existing_rule_id)
    end
  end
end
