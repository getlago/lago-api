# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Integrations::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyIntegrationInput!) {
        destroyIntegration(input: $input) { id }
      }
    GQL
  end

  it 'deletes an integration' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: { id: integration.id },
      },
    )

    data = result['data']['destroyIntegration']
    expect(data['id']).to eq(integration.id)
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: { id: integration.id },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
