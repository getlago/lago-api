# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiKeys::RotateService, type: :service do
  describe '#call' do
    subject(:service_result) { described_class.call(api_key) }

    context 'when API key is provided' do
      let(:api_key) { create(:api_key) }
      let(:organization) { api_key.organization }

      it 'expires the API key' do
        expect { service_result }.to change(api_key, :expires_at).from(nil).to(Time)
      end

      it 'creates a new API key for organization' do
        expect { service_result }.to change(ApiKey, :count).by(1)

        expect(service_result.api_key)
          .to be_persisted
          .and have_attributes(organization:)
      end

      it 'sends an API key rotated email' do
        expect { service_result }
          .to have_enqueued_mail(ApiKeyMailer, :rotated).with hash_including(params: {api_key:})
      end
    end

    context 'when API key is missing' do
      let(:api_key) { nil }

      it 'does not creates a new API key for organization' do
        expect { service_result }.not_to change(ApiKey, :count)
      end

      it 'does not send an API key rotated email' do
        expect { service_result }.not_to have_enqueued_mail(ApiKeyMailer, :rotated)
      end

      it 'returns an error' do
        aggregate_failures do
          expect(service_result).not_to be_success
          expect(service_result.error).to be_a(BaseService::NotFoundFailure)
          expect(service_result.error.error_code).to eq('api_key_not_found')
        end
      end
    end
  end
end
