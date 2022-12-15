# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupons::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:create_args) do
      {
        name: 'Super Coupon',
        code: 'free-beer',
        organization_id: organization.id,
        coupon_type: 'fixed_amount',
        frequency: 'once',
        amount_cents: 100,
        amount_currency: 'EUR',
        expiration: 'time_limit',
        reusable: false,
        expiration_at: (Time.current + 3.days).end_of_day,
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a coupon' do
      expect { create_service.create(**create_args) }
        .to change(Coupon, :count).by(1)
    end

    it 'calls SegmentTrackJob' do
      coupon = create_service.create(**create_args).coupon

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'coupon_created',
        properties: {
          coupon_code: coupon.code,
          coupon_name: coupon.name,
          organization_id: coupon.organization_id,
        },
      )
    end

    context 'when coupon type is percentage' do
      let(:create_args) do
        {
          name: 'Super Coupon',
          code: 'free-beer',
          organization_id: organization.id,
          coupon_type: 'percentage',
          frequency: 'once',
          percentage_rate: 20.00,
          expiration: 'time_limit',
          expiration_date: (Time.current + 3.days).to_date,
        }
      end

      it 'creates a coupon' do
        expect { create_service.create(**create_args) }
          .to change(Coupon, :count).by(1)
      end
    end

    context 'with validation error' do
      before do
        create(
          :coupon,
          organization: organization,
          code: 'free-beer',
        )
      end

      it 'returns an error' do
        result = create_service.create(**create_args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:code]).to eq(['value_already_exist'])
        end
      end
    end
  end
end
