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
      query:,
    )

    memberships_response = result['data']['memberships']

    aggregate_failures do
      expect(memberships_response['collection'].count).to eq(organization.memberships.count)
      expect(memberships_response['collection'].first['id']).to eq(membership.id)

      expect(memberships_response['metadata']['currentPage']).to eq(1)
      expect(memberships_response['metadata']['totalCount']).to eq(1)
    end
  end

  describe 'traversal attack attempt' do
    let!(:other_org) { create(:organization) }

    let(:other_user) { create(:user) }
    let(:other_user_membership) { create(:membership, user: other_user, organization:) }
    let(:other_user_other_membership) { create(:membership, user: other_user, organization: other_org) }

    let(:query) do
      <<~GQL
        query {
          memberships(limit: 5) {
            collection {
              id
              user {
                organizations {
                  id #{organization_field}
                }
              }
            }
          }
        }
      GQL
    end

    let(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )
    end

    let(:other_org_result_data) do
      result.dig('data', 'memberships', 'collection')
        &.find { |h| h['id'] == other_user_membership.id }
        &.dig('user', 'organizations')
        &.find { |h| h['id'] == other_org.id }
    end

    before do
      other_user
      other_user_membership
      other_user_other_membership
    end

    context 'with non-sensitive field' do
      let(:organization_field) { 'name' }

      it 'allows the query' do
        expect(other_org_result_data).to eq(
          'id' => other_org.id,
          'name' => other_org.name,
        )
      end
    end

    context 'with sensitive field' do
      let(:organization_field) { 'apiKey' }

      it 'rejects the query for a sensitive field' do
        expect(other_org_result_data).to be nil
        expect_graphql_error(
          result:,
          message: "Field 'apiKey' doesn't exist on type 'SafeOrganization'",
        )
      end
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
      )

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end
end
