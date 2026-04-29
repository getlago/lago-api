# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::AddOns::UpdateService, type: :service do
  subject(:result) { described_class.call(quote_version:, id:, params:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:add_on) { create(:add_on, organization:) }
  let(:item_id) { "qta_#{SecureRandom.uuid}" }
  let(:quote) { create(:quote, :with_version, organization:, order_type: :one_off) }
  let(:quote_version) { quote.current_version }
  let(:id) { item_id }
  let(:params) { {name: "Updated Name"} }

  before do
    allow(License).to receive(:premium?).and_return(true)
    quote_version.update!(billing_items: {
      "add_ons" => [{"id" => item_id, "name" => "Original", "add_on_id" => add_on.id}]
    })
  end

  it "updates the add-on billing item" do
    expect(result).to be_success
    expect(result.quote_version.billing_items["add_ons"].first["name"]).to eq("Updated Name")
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
    let(:quote) { create(:quote, :with_version, organization:, order_type: :one_off, version_trait: :voided) }

    it "returns not allowed failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotAllowedFailure)
    end
  end

  context "when item id is not found" do
    let(:id) { "qta_nonexistent" }

    it "returns not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when name is blank" do
    let(:params) { {name: ""} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
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
