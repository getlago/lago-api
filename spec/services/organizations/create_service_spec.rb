# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organizations::CreateService, type: :service do
  describe '#call' do
    subject(:service_result) { described_class.call(params) }

    context 'with valid params' do
      let(:params) { attributes_for(:organization) }

      it 'creates an organization with provided params' do
        expect { service_result }.to change(Organization, :count).by(1)

        expect(service_result.organization)
          .to be_persisted
          .and have_attributes(params)
      end

      it 'creates an API key for created organization' do
        expect { service_result }.to change(ApiKey, :count).by(1)

        expect(service_result.organization.api_keys).to all(
          be_persisted.and(have_attributes(organization: service_result.organization))
        )
      end
    end

    context 'with invalid params' do
      let(:params) { {} }

      it 'does not create an organization' do
        expect { service_result }.not_to change(Organization, :count)
      end

      it 'does not create an API key' do
        expect { service_result }.not_to change(ApiKey, :count)
      end

      it 'returns an error' do
        aggregate_failures do
          expect(service_result).not_to be_success
          expect(service_result.error).to be_a(BaseService::ValidationFailure)
          expect(service_result.error.messages[:name]).to eq(["value_is_mandatory"])
        end
      end
    end
  end
end
