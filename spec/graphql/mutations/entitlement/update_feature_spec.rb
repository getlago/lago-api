# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Entitlement::UpdateFeature, type: :graphql do
  let(:required_permission) { "features:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:feature) do
    create(:feature, organization:)
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateFeatureInput!) {
        updateFeature(input: $input) {
          id
          name
          description
          code
          privileges { code name }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "features:update"

  it "updates a feature" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: feature.id,
          name: "Updated Feature Name",
          description: "Updated Feature Description",
          privileges: []
        }
      }
    )

    result_data = result["data"]["updateFeature"]

    expect(result_data["name"]).to eq("Updated Feature Name")
    expect(result_data["description"]).to eq("Updated Feature Description")
    expect(result_data["code"]).to eq(feature.code)
    expect(result_data["privileges"]).to be_empty
  end

  it "returns not found error for non-existent feature" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: "non-existent-id",
          name: "Updated Feature Name",
          description: "Updated Feature Description",
          privileges: []
        }
      }
    )

    expect(result["errors"]).to be_present
  end

  context "when creating new privileges" do
    let(:new_privilege_code) { "new_privilege" }
    let(:new_privilege_name) { "New Privilege" }

    it "adds new privileges to the feature" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: feature.id,
            name: "Updated Feature Name",
            description: "Updated Feature Description",
            privileges: [
              {code: new_privilege_code, name: new_privilege_name}
            ]
          }
        }
      )

      result_data = result["data"]["updateFeature"]

      expect(result_data["privileges"].size).to eq(1)
      expect(result_data["privileges"].sole["code"]).to eq(new_privilege_code)
      expect(result_data["privileges"].sole["name"]).to eq(new_privilege_name)
    end
  end
end
