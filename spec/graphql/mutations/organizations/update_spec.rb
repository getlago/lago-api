# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Organizations::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateOrganizationInput!) {
        updateOrganization(input: $input) {
          webhookUrl,
          vatRate
        }
      }
    GQL
  end

  it 'updates an organization' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          webhookUrl: 'http://foo.bar',
          vatRate: 12.5,
        },
      },
    )

    result_data = result['data']['updateOrganization']

    expect(result_data['webhookUrl']).to eq('http://foo.bar')
    expect(result_data['vatRate']).to eq(12.5)
  end

  context 'with invalid webhook url' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            webhookUrl: 'bad_url',
          },
        },
      )

      expect_graphql_error(result: result, message: :unprocessable_entity)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            webhookUrl: 'http://foo.bar',
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
            webhookUrl: 'http://foo.bar',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
