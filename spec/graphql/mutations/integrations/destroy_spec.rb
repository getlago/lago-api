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

  before { integration }

  it 'deletes an integration' do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: { id: integration.id },
        },
      )
    end.to change(::Integrations::BaseIntegration, :count).by(-1)
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: { id: integration.id },
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
          input: { id: integration.id },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
