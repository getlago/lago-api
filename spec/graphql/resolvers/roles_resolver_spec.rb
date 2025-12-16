# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RolesResolver do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:
    )
  end

  let(:query) do
    <<~GQL
      query {
        roles { id name description admin permissions }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  before do
    create(:role, :admin)
    create(:role, :finance)
    create(:role, organization:, name: "OPERATOR")
    create(:role, organization:, name: "accountant")
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"

  it "returns roles sorted by organization_id nulls first then by lower(name)" do
    roles_response = result["data"]["roles"]

    expect(roles_response.map { |r| r["name"] }).to eq(%w[Admin Finance accountant OPERATOR])
  end

  it "returns role attributes" do
    roles_response = result["data"]["roles"]
    admin_role = roles_response.find { |r| r["name"] == "Admin" }

    expect(admin_role["name"]).to eq("Admin")
    expect(admin_role["admin"]).to be(true)
    expect(admin_role["permissions"]).to eq([])
  end

  it "does not return roles from other organizations" do
    other_organization = create(:organization)
    create(:role, organization: other_organization, name: "OtherOrgRole")

    roles_response = result["data"]["roles"]

    expect(roles_response.map { |r| r["name"] }).not_to include("OtherOrgRole")
  end
end
