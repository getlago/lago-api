# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCoupon, type: :model do
  subject(:applied_coupon) { build(:applied_coupon) }

  it_behaves_like "paper_trail traceable"

  describe "#remaining_amount" do
    let(:credit) { build(:credit, applied_coupon:, amount_cents: 10) }
    let(:applied_coupon) { build(:applied_coupon, amount_cents: 50) }

    it "returns correct amount" do
      applied_coupon.credits = [credit]

      expect(applied_coupon.remaining_amount).to eq(40)
    end
  end

  describe "#mark_as_voided!" do
    let(:applied_coupon) { build(:applied_coupon, status: :active) }

    it "sets the status to voided and updates voided_at timestamp" do
      travel_to(Time.zone.local(2025, 1, 1, 15, 0)) do
        applied_coupon.mark_as_voided!
        expect(applied_coupon.voided_at).to eq(Time.current)
        expect(applied_coupon.status.to_sym).to eq(:voided)
      end
    end
  end
end
