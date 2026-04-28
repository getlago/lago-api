# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Coupons::AddService, type: :service do
  subject(:result) { described_class.call(quote_version:, params:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:coupon) { create(:coupon, organization:) }
  let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation) }
  let(:quote_version) { quote.current_version }
  let(:params) { {coupon_id: coupon.id, coupon_type: "fixed_amount"} }

  before { allow(License).to receive(:premium?).and_return(true) }

  it "adds the coupon to billing_items and returns the quote_version" do
    expect(result).to be_success
    expect(result.quote_version.billing_items["coupons"].length).to eq(1)
    expect(result.quote_version.billing_items["coupons"].first["coupon_id"]).to eq(coupon.id)
    expect(result.quote_version.billing_items["coupons"].first["id"]).to start_with("qtc_")
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

  context "when coupon_id is blank" do
    let(:params) { {coupon_type: "fixed_amount"} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when coupon does not belong to organization" do
    let(:params) { {coupon_id: create(:coupon).id, coupon_type: "fixed_amount"} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when coupon_type is invalid" do
    let(:params) { {coupon_id: coupon.id, coupon_type: "invalid"} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "with percentage coupon_type" do
    let(:params) { {coupon_id: coupon.id, coupon_type: "percentage"} }

    it "adds the coupon successfully" do
      expect(result).to be_success
      expect(result.quote_version.billing_items["coupons"].first["coupon_type"]).to eq("percentage")
    end
  end
end
