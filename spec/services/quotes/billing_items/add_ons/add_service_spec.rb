# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::AddOns::AddService, type: :service do
  subject(:result) { described_class.call(quote_version:, params:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:add_on) { create(:add_on, organization:) }
  let(:quote) { create(:quote, :with_version, organization:, order_type: :one_off) }
  let(:quote_version) { quote.current_version }
  let(:params) { {name: "My Add-on", add_on_id: add_on.id} }

  before { allow(License).to receive(:premium?).and_return(true) }

  it "adds the add-on to billing_items and returns the quote_version" do
    expect(result).to be_success
    expect(result.quote_version.billing_items["add_ons"].length).to eq(1)
    expect(result.quote_version.billing_items["add_ons"].first["add_on_id"]).to eq(add_on.id)
    expect(result.quote_version.billing_items["add_ons"].first["id"]).to start_with("qta_")
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
    let(:quote) { create(:quote, :with_version, organization:, order_type: :one_off, version_trait: :voided) }

    it "returns not allowed failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotAllowedFailure)
    end
  end

  context "when order_type is subscription_creation" do
    let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation) }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when name is blank" do
    let(:params) { {add_on_id: add_on.id} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when add_on_id is absent and amount_cents is missing" do
    let(:params) { {name: "Custom"} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when add_on_id is absent and amount_cents is provided" do
    let(:params) { {name: "Custom", amount_cents: 1000} }

    it "adds the item successfully" do
      expect(result).to be_success
      expect(result.quote_version.billing_items["add_ons"].first["amount_cents"]).to eq(1000)
    end
  end

  context "when add_on does not belong to organization" do
    let(:params) { {name: "Test", add_on_id: create(:add_on).id} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end
end
