# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::IntegrationMappings::Netsuite::Create, type: :graphql do
  let(:required_permission) { 'organization:integrations:update' }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:mappable) { create(:add_on, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:external_account_code) { Faker::Barcode.ean }
  let(:external_id) { SecureRandom.uuid }
  let(:external_name) { Faker::Commerce.department }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateNetsuiteIntegrationMappingInput!) {
        createNetsuiteIntegrationMapping(input: $input) {
          id,
          integrationId,
          mappableId,
          mappableType,
          externalAccountCode,
          externalId,
          externalName
        }
      }
    GQL
  end

  it_behaves_like 'requires permission', 'organization:integrations:update'

  it 'creates a netsuite integration mapping' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          integrationId: integration.id,
          mappableId: mappable.id,
          mappableType: 'AddOn',
          externalAccountCode: external_account_code,
          externalId: external_id,
          externalName: external_name,
        },
      },
    )

    result_data = result['data']['createNetsuiteIntegrationMapping']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['integrationId']).to eq(integration.id)
      expect(result_data['mappableId']).to eq(mappable.id)
      expect(result_data['mappableType']).to eq('AddOn')
      expect(result_data['externalAccountCode']).to eq(external_account_code)
      expect(result_data['externalId']).to eq(external_id)
      expect(result_data['externalName']).to eq(external_name)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            integrationId: integration.id,
            mappableId: mappable.id,
            mappableType: 'AddOn',
            externalAccountCode: external_account_code,
            externalId: external_id,
            externalName: external_name,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            integrationId: integration.id,
            mappableId: mappable.id,
            mappableType: 'AddOn',
            externalAccountCode: external_account_code,
            externalId: external_id,
            externalName: external_name,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
