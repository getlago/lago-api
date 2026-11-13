# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Admin::LinkSandboxOrganization do
  include_context "with self-serve enabled"

  let(:query) do
    <<~GQL
      mutation($input: AdminLinkSandboxOrganizationInput!) {
        adminLinkSandboxOrganization(input: $input) {
          organization { id sandboxOrganization { id } }
          sandboxOrganization { id environment }
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:production) { create(:organization) }
  let(:target) { create(:organization) }

  def link(current_user: admin_user, sandbox_organization_id: target.id)
    input = {productionOrganizationId: production.id, sandboxOrganizationId: sandbox_organization_id,
             reason: "Linking the customer's test organization"}
    execute_graphql(current_user:, query:, variables: {input:})
  end

  it "links the sandbox", :premium do
    payload = link["data"]["adminLinkSandboxOrganization"]

    expect(payload).to eq(
      "organization" => {"id" => production.id, "sandboxOrganization" => {"id" => target.id}},
      "sandboxOrganization" => {"id" => target.id, "environment" => "sandbox"}
    )
  end

  it "answers not found for an unknown or malformed id", :premium do
    expect(link(sandbox_organization_id: "not-a-uuid")["errors"].first["extensions"]["code"]).to eq("not_found")
  end

  context "with a CS admin", :premium do
    subject(:result) { link }

    it_behaves_like "a self-serve entry point"
  end

  context "when self-serve is off", :premium do
    let(:self_serve_env) { {"LAGO_SELF_SERVE_ENABLED" => "false"} }

    it "refuses a user who is not a CS admin as unauthorized" do
      expect(link(current_user: create(:user))["errors"].first["extensions"]["code"]).to eq("unauthorized")
    end
  end

  it "refuses a user who is not a CS admin", :premium do
    result = link(current_user: create(:user))

    expect(result["errors"].first["extensions"]["code"]).to eq("unauthorized")
    expect(target.reload).to be_production
  end
end
