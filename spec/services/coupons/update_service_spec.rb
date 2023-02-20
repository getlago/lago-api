# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupons::UpdateService, type: :service do
  subject(:update_service) { described_class.new(coupon:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:coupon) { create(:coupon, organization:) }

  let(:params) do
    {
      name:,
      coupon_type: 'fixed_amount',
      frequency: 'once',
      amount_cents: 100,
      amount_currency: 'EUR',
      expiration: 'time_limit',
      reusable: false,
      expiration_at:,
      applies_to:,
    }
  end

  let(:name) { 'new name' }
  let(:expiration_at) { Time.current + 30.days }
  let(:applies_to) { nil }

  describe '#call' do
    it 'updates the coupon' do
      result = update_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.coupon.name).to eq('new name')
        expect(result.coupon.amount_cents).to eq(100)
        expect(result.coupon.amount_currency).to eq('EUR')
        expect(result.coupon.expiration).to eq('time_limit')
        expect(result.coupon.reusable).to eq(false)
        expect(result.coupon.expiration_at.to_s).to eq(expiration_at.to_s)
      end
    end

    context 'with validation error' do
      let(:name) { nil }

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end
    end

    context 'with new plan limitations' do
      let(:plan) { create(:plan, organization:) }
      let(:plan_second) { create(:plan, organization:) }
      let(:coupon_plan) { create(:coupon_plan, coupon:, plan:) }
      let(:applies_to) { { plan_ids: [plan.id, plan_second.id] } }

      before do
        CurrentContext.source = 'graphql'

        plan_second
        coupon_plan
      end

      it 'creates new coupon plans' do
        expect { update_service.call }.to change(CouponPlan, :count).by(1)
      end

      context 'with API context' do
        before { CurrentContext.source = 'api' }

        let(:applies_to) { { plan_codes: [plan.code, plan_second.code] } }

        it 'creates new coupon plans using plan code' do
          expect { update_service.call }.to change(CouponPlan, :count).by(1)
        end
      end
    end

    context 'with coupon plans to delete' do
      let(:plan) { create(:plan, organization:) }
      let(:coupon_plan) { create(:coupon_plan, coupon:, plan:) }
      let(:applies_to) { { plan_ids: [] } }

      before do
        CurrentContext.source = 'graphql'

        coupon_plan
      end

      it 'deletes a coupon plan' do
        expect { update_service.call }.to change(CouponPlan, :count).by(-1)
      end
    end

    context 'when coupon is not found' do
      let(:coupon) { nil }

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq('coupon_not_found')
        end
      end
    end
  end
end
