# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Integrations::Okta::Create, type: :graphql do
  let(:required_permission) { 'organization:integrations:create' }
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateOktaIntegrationInput!) {
        createOktaIntegration(input: $input) {
          id,
          name,
          code,
          clientId,
          clientSecret,
          domain,
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before { membership.organization.update!(premium_integrations: ['okta']) }

  it_behaves_like 'requires permission', 'organization:integrations:create'

  it 'creates an okta integration' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          clientId: '123',
          clientSecret: '456',
          domain: 'foo.bar',
          organizationName: 'Foobar',
        },
      },
    )

    result_data = result['data']['createOktaIntegration']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['code']).to eq('okta')
      expect(result_data['name']).to eq('Okta Integration')
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            clientId: '123',
            clientSecret: '456',
            domain: 'foo.bar',
            organizationName: 'Foobar',
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
            clientId: '123',
            clientSecret: '456',
            domain: 'foo.bar',
            organizationName: 'Foobar',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
