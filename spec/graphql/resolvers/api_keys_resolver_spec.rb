# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ApiKeysResolver, type: :graphql do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )
  end

  let(:query) do
    <<~GQL
      query {
        apiKeys(limit: 1, page: 2) {
          collection { id value createdAt }
          metadata { currentPage, totalCount totalPages }
        }
      }
    GQL
  end

  let(:organization) { create(:api_key).organization }
  let(:membership) { create(:membership, organization:) }
  let(:required_permission) { "developers:keys:manage" }
  let!(:api_key) { create(:api_key, organization:) }

  before { create(:api_key) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "developers:keys:manage"

  it "returns a list of api keys" do
    api_key_response = result["data"]["apiKeys"]

    aggregate_failures do
      expect(api_key_response["collection"].first["id"]).to eq(api_key.id)
      expect(api_key_response["collection"].first["value"]).to eq("••••••••" + api_key.value.last(3))
      expect(api_key_response["collection"].first["createdAt"]).to eq(api_key.created_at.iso8601)

      expect(api_key_response["metadata"]["currentPage"]).to eq(2)
      expect(api_key_response["metadata"]["totalCount"]).to eq(2)
      expect(api_key_response["metadata"]["totalPages"]).to eq(2)
    end
  end
end
