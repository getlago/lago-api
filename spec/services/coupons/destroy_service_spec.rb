# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupons::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(coupon:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:coupon) { create(:coupon, organization:) }

  describe '#call' do
    before { coupon }

    it 'destroys the coupon' do
      expect { destroy_service.call }.to change(Coupon, :count).by(-1)
    end

    context 'when coupon is not found' do
      let(:coupon) { nil }

      it 'returns an error' do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('coupon_not_found')
        end
      end
    end

    context 'when coupon is attached to customer' do
      let(:applied_coupon) { create(:applied_coupon, coupon:) }

      before { applied_coupon }

      it 'returns an error' do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq('attached_to_an_active_customer')
        end
      end
    end
  end
end
