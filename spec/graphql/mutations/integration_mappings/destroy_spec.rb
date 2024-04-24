# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::IntegrationMappings::Destroy, type: :graphql do
  let(:integration_mapping) { create(:netsuite_mapping, integration:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyIntegrationMappingInput!) {
        destroyIntegrationMapping(input: $input) { id }
      }
    GQL
  end

  before { integration_mapping }

  it 'deletes an integration mapping' do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: { id: integration_mapping.id },
        },
      )
    end.to change(::IntegrationMappings::BaseMapping, :count).by(-1)
  end

  context 'when integration mapping is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: { id: '123456' },
        },
      )

      expect_not_found(result)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: { id: integration_mapping.id },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: { id: integration_mapping.id },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
