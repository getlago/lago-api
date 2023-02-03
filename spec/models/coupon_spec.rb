# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupon, type: :model do
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
