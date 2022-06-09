# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:payment_provider) { create(:stripe_provider, organization: organization) }

  describe '.destroy' do
    before { payment_provider }

    it 'destroys the payment_provider' do
      expect { destroy_service.destroy(id: payment_provider.id) }
        .to change(PaymentProviders::BaseProvider, :count).by(-1)
    end

    context 'when coupon is not found' do
      it 'returns an error' do
        result = destroy_service.destroy(id: nil)

        expect(result).not_to be_success
        expect(result.error).to eq('not_found')
      end
    end

    context 'when coupon is not attached to the organization' do
      let(:payment_provider) { create(:stripe_provider) }

      it 'returns an error' do
        result = destroy_service.destroy(id: payment_provider.id)

        expect(result).not_to be_success
        expect(result.error).to eq('not_found')
      end
    end
  end
end
