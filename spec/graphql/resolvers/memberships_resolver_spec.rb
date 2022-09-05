# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::MembershipsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        memberships(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it 'returns a list of memberships' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
    )

    memberships_response = result['data']['memberships']

    aggregate_failures do
      expect(memberships_response['collection'].count).to eq(organization.memberships.count)
      expect(memberships_response['collection'].first['id']).to eq(membership.id)

      expect(memberships_response['metadata']['currentPage']).to eq(1)
      expect(memberships_response['metadata']['totalCount']).to eq(1)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
      )

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
      )
    end
  end
end
