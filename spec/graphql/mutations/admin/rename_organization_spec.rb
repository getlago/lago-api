# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Admin::RenameOrganization do
  let(:query) do
    <<~GQL
      mutation($input: AdminRenameOrganizationInput!) {
        adminRenameOrganization(input: $input) {
          id action featureType featureKey organizationId reason
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization, name: "Old Name") }

  def rename(current_user: admin_user, organization_id: organization.id, name: "New Name")
    execute_graphql(
      current_user:,
      query:,
      variables: {
        input: {
          organizationId: organization_id,
          name:,
          reason: "Customer rebranded their company"
        }
      }
    )
  end

  it "renames the organization and returns the audit log", :premium do
    result = rename

    log = result["data"]["adminRenameOrganization"]
    expect(log["action"]).to eq("org_renamed")
    expect(log["featureType"]).to eq("organization")
    expect(log["featureKey"]).to eq("name")
    expect(log["organizationId"]).to eq(organization.id)
    expect(log["reason"]).to include("Renamed from \"Old Name\" to \"New Name\"")

    expect(organization.reload.name).to eq("New Name")
  end

  context "when the organization does not exist", :premium do
    it "returns a not found error" do
      result = rename(organization_id: SecureRandom.uuid)

      expect_graphql_error(result:, message: "not_found")
    end
  end

  context "when the name is unchanged", :premium do
    it "returns a validation error" do
      result = rename(name: "Old Name")

      expect_graphql_error(result:, message: "unprocessable_entity")
    end
  end

  it_behaves_like "a CS admin operation" do
    subject(:response) { rename(current_user:) }
  end
end
