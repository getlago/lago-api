# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupons::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(coupon:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon) { create(:coupon, organization:) }

  describe '#call' do
    before { coupon }

    it 'soft deletes the coupon' do
      aggregate_failures do
        expect { destroy_service.call }.to change(Coupon, :count).by(-1)
          .and change { coupon.reload.deleted_at }.from(nil)
      end
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
  end
end
