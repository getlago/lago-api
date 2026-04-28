# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Coupons::UpdateService, type: :service do
  subject(:result) { described_class.call(quote_version:, id:, params:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:coupon) { create(:coupon, organization:) }
  let(:new_coupon) { create(:coupon, organization:) }
  let(:item_id) { "qtc_#{SecureRandom.uuid}" }
  let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation) }
  let(:quote_version) { quote.current_version }
  let(:id) { item_id }
  let(:params) { {coupon_id: new_coupon.id} }

  before do
    allow(License).to receive(:premium?).and_return(true)
    quote_version.update!(billing_items: {
      "coupons" => [{"id" => item_id, "coupon_id" => coupon.id, "coupon_type" => "fixed_amount"}]
    })
  end

  it "updates the coupon billing item" do
    expect(result).to be_success
    expect(result.quote_version.billing_items["coupons"].first["coupon_id"]).to eq(new_coupon.id)
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
    let(:id) { "qtc_nonexistent" }

    it "returns not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when coupon_id is blank" do
    let(:params) { {coupon_id: ""} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when coupon does not belong to organization" do
    let(:params) { {coupon_id: create(:coupon).id} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when coupon_type is invalid" do
    let(:params) { {coupon_type: "invalid"} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end
end
