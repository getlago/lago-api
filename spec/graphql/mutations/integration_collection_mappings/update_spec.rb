# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::IntegrationCollectionMappings::Update, type: :graphql do
  let(:required_permission) { 'organization:integrations:update' }
  let(:integration_collection_mapping) { create(:netsuite_collection_mapping, integration:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:mapping_type) { %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit].sample.to_s }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:external_account_code) { Faker::Barcode.ean }
  let(:external_id) { SecureRandom.uuid }
  let(:external_name) { Faker::Commerce.department }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateIntegrationCollectionMappingInput!) {
        updateIntegrationCollectionMapping(input: $input) {
          id,
          integrationId,
          mappingType,
          externalAccountCode,
          externalId,
          externalName
        }
      }
    GQL
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:update'

  it 'updates a netsuite integration' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: integration_collection_mapping.id,
          integrationId: integration.id,
          mappingType: mapping_type,
          externalAccountCode: external_account_code,
          externalId: external_id,
          externalName: external_name
        }
      },
    )

    result_data = result['data']['updateIntegrationCollectionMapping']

    aggregate_failures do
      expect(result_data['integrationId']).to eq(integration.id)
      expect(result_data['mappingType']).to eq(mapping_type)
      expect(result_data['externalAccountCode']).to eq(external_account_code)
      expect(result_data['externalId']).to eq(external_id)
      expect(result_data['externalName']).to eq(external_name)
    end
  end
end
