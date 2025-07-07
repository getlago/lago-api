# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Entitlement::DestroyFeature, type: :graphql do
  let(:required_permission) { "features:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:feature) do
    create(:feature, organization:)
  end

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyFeatureInput!) {
        destroyFeature(input: $input) {
          id
          code
          name
          description
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "features:delete"

  it "destroys a feature" do
    expect { feature }.to change(Entitlement::Feature, :count).by(1)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: feature.id
        }
      }
    )

    result_data = result["data"]["destroyFeature"]

    expect(result_data["id"]).to eq(feature.id)
    expect(result_data["code"]).to eq(feature.code)
    expect(result_data["name"]).to eq(feature.name)
    expect(result_data["description"]).to eq(feature.description)
  end

  it "returns not found error for non-existent feature" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: "non-existent-id"
        }
      }
    )

    expect(result["errors"]).to be_present
  end
end
