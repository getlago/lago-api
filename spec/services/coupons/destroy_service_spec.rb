# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupons::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(coupon:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon) { create(:coupon, organization:) }
  let(:coupon_plan) { create(:coupon_plan, coupon:) }

  describe '#call' do
    before { coupon }

    it 'soft deletes the coupon' do
      freeze_time do
        expect { destroy_service.call }.to change(Coupon, :count).by(-1)
          .and change { coupon.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it 'soft deletes all the related coupon_plans' do
      freeze_time do
        expect { destroy_service.call }.to change { coupon_plan.reload.deleted_at }
          .from(nil).to(Time.current)
      end
    end

    context 'with applied coupons' do
      it 'terminates applied coupons' do
        applied_coupon = create(:applied_coupon, coupon:)
        result = destroy_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(applied_coupon.reload).to be_terminated
        end
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
