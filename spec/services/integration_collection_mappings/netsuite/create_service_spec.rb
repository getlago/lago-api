# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationCollectionMappings::Netsuite::CreateService, type: :service do
  let(:service) { described_class.new(membership.user) }

  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:add_on) { create(:add_on, organization:) }

  describe '#call' do
    subject(:service_call) { service.call(**create_args) }

    let(:create_args) do
      {
        mapping_type: :fallback_item,
        integration_id: integration.id,
      }
    end

    context 'without validation errors' do
      it 'creates an integration' do
        expect { service_call }.to change(IntegrationCollectionMappings::NetsuiteCollectionMapping, :count).by(1)

        integration_collection_mapping =
          IntegrationCollectionMappings::NetsuiteCollectionMapping.order(:created_at).last

        aggregate_failures do
          expect(integration_collection_mapping.mapping_type).to eq('fallback_item')
          expect(integration_collection_mapping.integration_id).to eq(integration.id)
        end
      end

      it 'returns an integration collection mapping in result object' do
        result = service_call

        expect(result.integration_collection_mapping).to be_a(IntegrationCollectionMappings::NetsuiteCollectionMapping)
      end
    end

    context 'with validation error' do
      let(:create_args) do
        {
          mappable_type: 'AddOn',
          mappable_id: add_on.id,
        }
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
