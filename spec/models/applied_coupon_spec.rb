# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedCoupon, type: :model do
  subject(:applied_coupon) { build(:applied_coupon) }

  it_behaves_like 'paper_trail traceable'

  describe '#remaining_amount' do
    let(:credit) { build(:credit, applied_coupon:, amount_cents: 10) }
    let(:applied_coupon) { build(:applied_coupon, amount_cents: 50) }

    it 'returns correct amount' do
      applied_coupon.credits = [credit]

      expect(applied_coupon.remaining_amount).to eq(40)
    end
  end
end
