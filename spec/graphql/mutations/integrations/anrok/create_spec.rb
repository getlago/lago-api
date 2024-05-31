# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Integrations::Anrok::Create, type: :graphql do
  let(:required_permission) { 'organization:integrations:create' }
  let(:membership) { create(:membership) }
  let(:code) { 'anrok1' }
  let(:name) { 'Anrok 1' }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateAnrokIntegrationInput!) {
        createAnrokIntegration(input: $input) {
          id,
          code,
          name,
          apiKey
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before { membership.organization.update!(premium_integrations: ['anrok']) }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:create'

  it 'creates an anrok integration' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          code:,
          name:,
          apiKey: '123456789'
        }
      },
    )

    result_data = result['data']['createAnrokIntegration']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['code']).to eq(code)
      expect(result_data['name']).to eq(name)
      expect(result_data['apiKey']).to eq('••••••••…789')
    end
  end
end
