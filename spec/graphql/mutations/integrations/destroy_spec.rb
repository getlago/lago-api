# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Integrations::Destroy, type: :graphql do
  let(:required_permission) { 'organization:integrations:delete' }
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

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:delete'

  it 'deletes an integration' do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: integration.id},
        },
      )
    end.to change(::Integrations::BaseIntegration, :count).by(-1)
  end
end
