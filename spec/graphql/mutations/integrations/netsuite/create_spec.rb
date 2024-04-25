# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Integrations::Netsuite::Create, type: :graphql do
  let(:required_permission) { 'organization:integrations:create' }
  let(:membership) { create(:membership) }
  let(:code) { 'netsuite1' }
  let(:name) { 'Netsuite 1' }
  let(:script_endpoint_url) { Faker::Internet.url }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateNetsuiteIntegrationInput!) {
        createNetsuiteIntegration(input: $input) {
          id,
          code,
          name,
          clientId,
          clientSecret,
          syncSalesOrders,
          syncInvoices,
          syncCreditNotes,
          syncPayments,
          scriptEndpointUrl
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before { membership.organization.update!(premium_integrations: ['netsuite']) }

  it_behaves_like 'requires permission', 'organization:integrations:create'

  it 'creates a netsuite integration' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          code:,
          name:,
          scriptEndpointUrl: script_endpoint_url,
          accountId: '012',
          clientId: '123',
          clientSecret: '456',
          connectionId: 'this-is-random-uuid',
        },
      },
    )

    result_data = result['data']['createNetsuiteIntegration']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['code']).to eq(code)
      expect(result_data['name']).to eq(name)
      expect(result_data['scriptEndpointUrl']).to eq(script_endpoint_url)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            code:,
            name:,
            accountId: '012',
            clientId: '123',
            clientSecret: '456',
            connectionId: 'this-is-random-uuid',
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
            code:,
            name:,
            accountId: '012',
            clientId: '123',
            clientSecret: '456',
            connectionId: 'this-is-random-uuid',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
