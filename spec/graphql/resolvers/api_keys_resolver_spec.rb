# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::ApiKeysResolver, type: :graphql do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query:
    )
  end

  let(:query) do
    <<~GQL
      query {
        apiKeys(limit: 5) {
          collection { id value createdAt }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:required_permission) { 'developers:keys:manage' }
  let(:api_key) { membership.organization.api_keys.first }

  before { create(:api_key) }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'developers:keys:manage'

  it 'returns a list of api keys' do
    api_key_response = result['data']['apiKeys']

    aggregate_failures do
      expect(api_key_response['collection'].first['id']).to eq(api_key.id)
      expect(api_key_response['collection'].first['value']).to eq("••••••••" + api_key.value.last(3))
      expect(api_key_response['collection'].first['createdAt']).to eq(api_key.created_at.iso8601)

      expect(api_key_response['metadata']['currentPage']).to eq(1)
      expect(api_key_response['metadata']['totalCount']).to eq(1)
    end
  end
end
