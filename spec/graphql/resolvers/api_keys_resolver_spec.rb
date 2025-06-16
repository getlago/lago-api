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
        apiKeys(limit: 1, page: 1) {
          collection { id value createdAt }
          metadata { currentPage, totalCount totalPages }
        }
      }
    GQL
  end

  let(:organization) { create(:api_key).organization }
  let(:membership) { create(:membership, organization:) }
  let(:required_permission) { "developers:keys:manage" }
  let(:api_key) { membership.organization.api_keys.first }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "developers:keys:manage"

  it "returns a list of api keys" do
    api_key_response = result["data"]["apiKeys"]

    expect(api_key_response["collection"].first["id"]).to eq(api_key.id)
    expect(api_key_response["collection"].first["value"]).to eq("••••••••" + api_key.value.last(3))
    expect(api_key_response["collection"].first["createdAt"]).to eq(api_key.created_at.iso8601)

    expect(api_key_response["metadata"]["currentPage"]).to eq(1)
    expect(api_key_response["metadata"]["totalCount"]).to eq(1)
    expect(api_key_response["metadata"]["totalPages"]).to eq(1)
  end

  context "when pagination is provided" do
    let(:query) do
      <<~GQL
        query {
          apiKeys(limit: 2, page: 2) {
            collection { id value name createdAt }
            metadata { currentPage, totalCount totalPages}
          }
        }
      GQL
    end

    before do
      3.times do |i|
        create(:api_key, organization: membership.organization, created_at: Time.zone.now - 10.days + i.days, name: "API Key #{i + 1}")
      end
    end

    it "returns a list of api keys" do
      api_key_response = result["data"]["apiKeys"]

      collection = api_key_response["collection"]

      expect(collection.size).to eq(2)
      expect(collection.map { |api_key| api_key["name"] }).to eq(["API Key 3", "API Key"])

      expect(api_key_response["metadata"]["currentPage"]).to eq(2)
      expect(api_key_response["metadata"]["totalCount"]).to eq(4)
      expect(api_key_response["metadata"]["totalPages"]).to eq(2)
    end
  end
end
