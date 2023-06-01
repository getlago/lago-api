# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::AdyenService, type: :service do
  subject(:adyen_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:api_key) { 'test_api_key_1' }
  let(:merchant_account) { 'LagoMerchant' }

  describe '.create_or_update' do
    it 'creates an adyen provider' do
      expect do
        adyen_service.create_or_update(organization:, api_key:, merchant_account:)
      end.to change(PaymentProviders::AdyenProvider, :count).by(1)
    end

    context 'when organization already has an adyen provider' do
      let(:adyen_provider) do
        create(:adyen_provider, organization:, api_key: 'api_key_789')
      end

      before { adyen_provider }

      it 'updates the existing provider' do
        result = adyen_service.create_or_update(
          organization:,
          api_key:,
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.adyen_provider.id).to eq(adyen_provider.id)
          expect(result.adyen_provider.api_key).to eq('test_api_key_1')
        end
      end
    end

    context 'with validation error' do
      let(:token) { nil }

      it 'returns an error result' do
        result = adyen_service.create_or_update(
          organization:,
          api_key: nil,
          merchant_account: nil,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:api_key]).to eq(['value_is_mandatory'])
          expect(result.error.messages[:merchant_account]).to eq(['value_is_mandatory'])
        end
      end
    end
  end
end
