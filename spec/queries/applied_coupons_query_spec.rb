# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCouponsQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:)
  end

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:customer) { create(:customer, organization:) }
  let(:coupon) { create(:coupon, organization:) }

  let(:applied_coupon) { create(:applied_coupon, coupon:, customer:) }

  before { applied_coupon }

  it "returns a list of applied_coupons" do
    expect(result).to be_success
    expect(result.applied_coupons.count).to eq(1)
    expect(result.applied_coupons).to eq([applied_coupon])
  end

  context "when applied coupons have the same values for the ordering criteria" do
    let(:applied_coupon_2) do
      create(
        :applied_coupon,
        coupon:,
        customer:,
        id: "00000000-0000-0000-0000-000000000000",
        created_at: applied_coupon.created_at
      )
    end

    before { applied_coupon_2 }

    it "returns a consistent list" do
      expect(result).to be_success
      expect(result.applied_coupons.count).to eq(2)
      expect(result.applied_coupons).to eq([applied_coupon_2, applied_coupon])
    end
  end

  context "when customer is deleted" do
    let(:customer) { create(:customer, :deleted, organization:) }

    it "filters the applied_coupons" do
      expect(result).to be_success
      expect(result.applied_coupons.count).to eq(0)
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 10} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.applied_coupons.count).to eq(0)
      expect(result.applied_coupons.current_page).to eq(2)
    end
  end

  context "with customer filter" do
    let(:filters) { {external_customer_id: customer.external_id} }

    it "applies the filter" do
      expect(result).to be_success
      expect(result.applied_coupons.count).to eq(1)
    end
  end

  context "with status filter" do
    let(:filters) { {status: "terminated"} }

    it "applies the filter" do
      expect(result).to be_success
      expect(result.applied_coupons.count).to eq(0)
    end
  end
end
