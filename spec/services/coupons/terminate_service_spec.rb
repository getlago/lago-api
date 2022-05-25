# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupons::TerminateService, type: :service do
  subject(:terminate_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:coupon) { create(:coupon, organization: organization) }

  describe 'terminate' do
    it 'terminates the coupon' do
      result = terminate_service.terminate(coupon.id)

      expect(result).to be_success
      expect(result.coupon).to be_terminated
    end

    context 'when coupon is already terminated' do
      before { coupon.mark_as_terminated! }

      it 'does not impact the coupon' do
        terminated_at = coupon.terminated_at
        result = terminate_service.terminate(coupon.id)

        expect(result).to be_success
        expect(result.coupon).to be_terminated
        expect(result.coupon.terminated_at).to eq(terminated_at)
      end
    end
  end

  describe 'terminate_all_expired' do
    let(:to_expire_coupons) do
      create_list(
        :coupon,
        3,
        organization: organization,
        status: 'active',
        expiration: 'time_limit',
        expiration_duration: rand(1..30),
        created_at: Time.zone.now - 40.days,
      )
    end

    let(:to_keep_active_coupons) do
      create_list(
        :coupon,
        3,
        organization: organization,
        status: 'active',
        expiration: 'time_limit',
        expiration_duration: rand(1..30),
        created_at: Time.zone.now,
      )
    end

    let(:to_expire_applied_coupon) do
      create(
        :applied_coupon,
        coupon: to_expire_coupons.last,
        status: 'active',
      )
    end

    let(:to_keep_active_applied_coupon) do
      create(
        :applied_coupon,
        coupon: to_keep_active_coupons.last,
        status: 'active',
      )
    end

    before do
      to_expire_applied_coupon
      to_keep_active_applied_coupon

      terminate_service.terminate_all_expired
    end

    it 'terminates the expired coupons' do
      expect(Coupon.terminated.count).to eq(3)
    end

    it 'expires the applied coupons' do
      expect(to_expire_applied_coupon.reload).to be_terminated
    end

    it 'does not update other applied coupons' do
      expect(to_keep_active_applied_coupon.reload).to be_active
    end
  end
end
