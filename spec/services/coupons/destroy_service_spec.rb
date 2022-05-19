# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupons::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:coupon) { create(:coupon, organization: organization) }

  describe 'destroy' do
    before { coupon }

    it 'destroys the coupon' do
      expect { destroy_service.destroy(coupon.id) }
        .to change(Coupon, :count).by(-1)
    end

    context 'when coupon is not found' do
      it 'returns an error' do
        result = destroy_service.destroy(nil)

        expect(result).not_to be_success
        expect(result.error).to eq('not_found')
      end
    end

    # context 'when coupon is attached to customers' do
    #   # TODO
    # end
  end
end
