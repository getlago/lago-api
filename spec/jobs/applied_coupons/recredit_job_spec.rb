# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCoupons::RecreditJob do
  subject(:perform_job) { described_class.perform_now(credit) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:coupon) { create(:coupon, organization:) }
  let(:applied_coupon) { create(:applied_coupon, organization:, customer:, coupon:, frequency:, status:) }
  let(:credit) { create(:credit, organization:, invoice:, applied_coupon:) }
  let(:frequency) { "once" }
  let(:status) { "active" }

  before { allow(AppliedCoupons::RecreditService).to receive(:call!) }

  context "when the applied coupon is once and terminated" do
    let(:frequency) { "once" }
    let(:status) { "terminated" }

    it "delegates to AppliedCoupons::RecreditService" do
      perform_job

      expect(AppliedCoupons::RecreditService).to have_received(:call!).with(credit:)
    end
  end

  context "when the applied coupon is recurring and active" do
    let(:frequency) { "recurring" }
    let(:status) { "active" }
    let(:applied_coupon) do
      create(:applied_coupon, organization:, customer:, coupon:,
        frequency:, status:, frequency_duration: 3, frequency_duration_remaining: 2)
    end

    it "delegates to AppliedCoupons::RecreditService" do
      perform_job

      expect(AppliedCoupons::RecreditService).to have_received(:call!).with(credit:)
    end
  end

  context "when the applied coupon is forever" do
    let(:frequency) { "forever" }
    let(:status) { "active" }

    it "delegates to AppliedCoupons::RecreditService" do
      perform_job

      expect(AppliedCoupons::RecreditService).to have_received(:call!).with(credit:)
    end
  end

  context "when the applied coupon is nil" do
    before { credit.update!(applied_coupon: nil) }

    it "does not call AppliedCoupons::RecreditService" do
      perform_job

      expect(AppliedCoupons::RecreditService).not_to have_received(:call!)
    end
  end
end
