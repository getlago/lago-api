# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationMappings::Netsuite::UpdateService, type: :service do
  let(:integration_mapping) { create(:netsuite_mapping, integration:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }

  describe '#call' do
    subject(:service_call) { described_class.call(integration_mapping:, params: update_args) }

    before { integration_mapping }

    let(:update_args) do
      {
        netsuite_id: '456',
        netsuite_name: 'Name1',
        netsuite_account_code: 'code-2',
      }
    end

    context 'without validation errors' do
      it 'updates an integration mapping' do
        service_call

        integration_mapping = IntegrationMappings::NetsuiteMapping.order(:updated_at).last

        aggregate_failures do
          expect(integration_mapping.netsuite_id).to eq('456')
          expect(integration_mapping.netsuite_name).to eq('Name1')
          expect(integration_mapping.netsuite_account_code).to eq('code-2')
        end
      end

      it 'returns an integration mapping in result object' do
        result = service_call

        expect(result.integration_mapping).to be_a(IntegrationMappings::NetsuiteMapping)
      end
    end

    context 'with validation error' do
      let(:update_args) do
        { integration_id: nil }
      end

      it 'returns an error' do
        result = service_call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:integration]).to eq(['relation_must_exist'])
        end
      end
    end
  end
end
