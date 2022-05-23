# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupon, type: :model do
  describe 'attached_to_customers?' do
    let(:coupon) { create(:coupon) }

    it { expect(coupon).not_to be_attached_to_customers }

    context 'with attached customers' do
      before { create(:applied_coupon, coupon: coupon) }

      it { expect(coupon).to be_attached_to_customers }
    end
  end

  describe 'deletable?' do
    let(:coupon) { create(:coupon) }

    it { expect(coupon).to be_deletable }

    context 'with attached customers' do
      before { create(:applied_coupon, coupon: coupon) }

      it { expect(coupon).not_to be_deletable }
    end
  end

  describe '.mark_as_terminated' do
    let(:coupon) { create(:coupon) }

    it 'terminates the coupon' do
      coupon.mark_as_terminated!

      aggregate_failures do
        expect(coupon).to be_terminated
        expect(coupon.terminated_at).to be_present
      end
    end
  end
end
