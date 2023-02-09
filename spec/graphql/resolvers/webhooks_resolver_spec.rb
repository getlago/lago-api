# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::WebhooksResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        webhooks(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  before do
    create_list(:webhook, 5, :succeeded, organization:)
  end

  it 'returns a list of webhooks' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
    )

    webhooks_response = result['data']['webhooks']

    aggregate_failures do
      expect(webhooks_response['collection'].count).to eq(organization.webhooks.count)
      expect(webhooks_response['metadata']['currentPage']).to eq(1)
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

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:,
      )

      expect_graphql_error(
        result:,
        message: 'Not in organization',
      )
    end
  end
end
