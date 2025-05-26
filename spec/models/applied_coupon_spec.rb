# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCoupon, type: :model do
  subject(:applied_coupon) { create(:applied_coupon) }

  it_behaves_like "paper_trail traceable"

  describe "#remaining_amount" do
    let(:invoice) { create(:invoice) }
    let(:credit) { create(:credit, applied_coupon:, amount_cents: 10, invoice:) }
    let(:applied_coupon) { create(:applied_coupon, amount_cents: 50) }

    it "returns correct amount" do
      applied_coupon.credits = [credit]
      expect(applied_coupon.remaining_amount).to eq(40)
    end

    context 'when invoice is voided' do
      let(:invoice) { create(:invoice, status: :voided) }
      
      it "does not count credits from voided invoices" do
        expect(applied_coupon.remaining_amount).to eq(50)
      end
    end
  end
end
