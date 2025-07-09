# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Entitlement::FeatureResolver, type: :graphql do
  let(:required_permission) { "features:view" }
  let(:query) do
    <<~GQL
      query($featureId: ID!) {
        feature(id: $featureId) {
          id
          code
          name
          description
          privileges {
            id
            code
            name
            valueType
            config
          }
          createdAt
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:feature) { create(:feature, organization:) }

  before do
    feature
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "features:view"

  it "returns a single feature" do
    privilege = create(:privilege, feature:, value_type: "boolean")

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {featureId: feature.id}
    )

    feature_response = result["data"]["feature"]

    expect(feature_response["id"]).to eq(feature.id)
    expect(feature_response["code"]).to eq(feature.code)
    expect(feature_response["name"]).to eq(feature.name)
    expect(feature_response["description"]).to eq(feature.description)
    expect(feature_response["createdAt"]).to be_present
    expect(feature_response["privileges"].count).to eq(1)
    expect(feature_response["privileges"].first["id"]).to eq(privilege.id)
    expect(feature_response["privileges"].first["code"]).to eq(privilege.code)
    expect(feature_response["privileges"].first["valueType"]).to eq(privilege.value_type)
    expect(feature_response["privileges"].first["config"]).to eq(privilege.config)
  end

  context "when feature is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {featureId: "invalid"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
