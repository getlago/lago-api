# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Integrations::Netsuite::Update, type: :graphql do
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:code) { 'netsuite1' }
  let(:name) { 'Netsuite 1' }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateNetsuiteIntegrationInput!) {
        updateNetsuiteIntegration(input: $input) {
          id,
          code,
          name,
          clientId,
          clientSecret,
          syncSalesOrders,
          syncInvoices,
          syncCreditNotes,
          syncPayments
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before do
    integration
    membership.organization.update!(premium_integrations: ['netsuite'])
  end

  it 'updates a netsuite integration' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          id: integration.id,
          name:,
          code:,
        },
      },
    )

    result_data = result['data']['updateNetsuiteIntegration']

    aggregate_failures do
      expect(result_data['name']).to eq(name)
      expect(result_data['code']).to eq(code)
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
            code:,
            name:,
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
        query: mutation,
        variables: {
          input: {
            id: integration.id,
            code:,
            name:,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
