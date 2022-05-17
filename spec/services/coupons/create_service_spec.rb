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
        coupon_type: 'free_days',
        day_count: 5,
      }
    end

    it 'creates a coupon' do
      expect { create_service.create(**create_args) }
        .to change(Coupon, :count).by(1)
    end

    context 'with validation error' do
      before do
        create(
          :free_days_coupon,
          organization: organization,
          code: 'free-beer',
        )
      end

      it 'returns an error' do
        result = create_service.create(**create_args)

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end
  end
end
