# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Integrations::Okta::Update, type: :graphql do
  let(:required_permission) { 'organization:integrations:update' }
  let(:integration) { create(:okta_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateOktaIntegrationInput!) {
        updateOktaIntegration(input: $input) {
          id,
          code,
          name,
          clientId,
          clientSecret,
          domain,
          organizationName,
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before do
    integration
    membership.organization.update!(premium_integrations: ['okta'])
  end

  it_behaves_like 'requires permission', 'organization:integrations:update'

  it 'updates an okta integration' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: integration.id,
          domain: 'foo.bar',
          organizationName: 'Footest',
        },
      },
    )

    result_data = result['data']['updateOktaIntegration']

    aggregate_failures do
      expect(result_data['domain']).to eq('foo.bar')
      expect(result_data['organizationName']).to eq('Footest')
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            id: integration.id,
            domain: 'foo.bar',
            organizationName: 'Footest',
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
            id: integration.id,
            domain: 'foo.bar',
            organizationName: 'Footest',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
