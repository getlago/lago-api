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

    context 'when coupon is attached to customer' do
      let(:applied_coupon) { create(:applied_coupon, coupon: coupon) }

      before { applied_coupon }

      it 'returns an error' do
        result = destroy_service.destroy(coupon.id)

        expect(result).not_to be_success
        expect(result.error_code).to eq('forbidden')
      end
    end
  end

  describe 'destroy_from_api' do
    let(:coupon) { create(:coupon, organization: organization) }

    it 'destroys the coupon' do
      code = coupon.code

      expect { destroy_service.destroy_from_api(organization: organization, code: code) }
        .to change(Coupon, :count).by(-1)
    end

    context 'when coupon is not found' do
      it 'returns an error' do
        result = destroy_service.destroy_from_api(organization: organization, code: 'invalid12345')

        expect(result).not_to be_success
        expect(result.error_code).to eq('not_found')
      end
    end

    context 'when coupon is attached to customer' do
      let(:applied_coupon) { create(:applied_coupon, coupon: coupon) }

      before { applied_coupon }

      it 'returns an error' do
        result = destroy_service.destroy_from_api(organization: organization, code: coupon.code)

        expect(result).not_to be_success
        expect(result.error_code).to eq('forbidden')
      end
    end
  end

  describe 'terminate' do
    it 'terminates the coupon' do
      result = destroy_service.terminate(coupon.id)

      expect(result).to be_success
      expect(result.coupon).to be_terminated
    end

    context 'when coupon is already terminated' do
      before { coupon.mark_as_terminated! }

      it 'does not impact the coupon' do
        terminated_at = coupon.terminated_at
        result = destroy_service.terminate(coupon.id)

        expect(result).to be_success
        expect(result.coupon).to be_terminated
        expect(result.coupon.terminated_at).to eq(terminated_at)
      end
    end
  end
end
