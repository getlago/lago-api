# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::AddOnResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($addOnId: ID!) {
        addOn(id: $addOnId) {
          id, name
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:add_on) { create(:add_on, organization: organization) }

  it 'returns a single add-on' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        addOnId: add_on.id,
      },
    )

    add_on_response = result['data']['addOn']

    aggregate_failures do
      expect(add_on_response['id']).to eq(add_on.id)
      expect(add_on_response['name']).to eq(add_on.name)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
        variables: {
          addOnId: add_on.id,
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
        )
    end
  end

  context 'when add-on is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
        variables: {
          addOnId: 'invalid',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
