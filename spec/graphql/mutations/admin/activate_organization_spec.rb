# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Admin::ActivateOrganization do
  include_context "with self-serve enabled"

  let(:query) do
    <<~GQL
      mutation($input: AdminActivateOrganizationInput!) {
        adminActivateOrganization(input: $input) { id activationStatus }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization, :self_serve, activation_status: "pending_payment_method") }

  def activate(current_user: admin_user, organization_id: organization.id)
    input = {organizationId: organization_id, reason: "Opened for a sales prospect"}
    execute_graphql(current_user:, query:, variables: {input:})
  end

  it "opens the organization", :premium do
    expect(activate["data"]["adminActivateOrganization"])
      .to eq("id" => organization.id, "activationStatus" => "active")
    expect(CsAdminAuditLog.where(organization:, action: :organization_activated).count).to eq(1)
  end

  it "answers not found for an unknown or malformed id", :premium do
    expect(activate(organization_id: "not-a-uuid")["errors"].first["extensions"]["code"]).to eq("not_found")
  end

  it "refuses an organization that is not self-serve", :premium do
    regular = create(:organization)

    expect(activate(organization_id: regular.id)["errors"].first["extensions"])
      .to eq("status" => 403, "code" => "organization_not_self_serve_production")
  end

  context "with a CS admin", :premium do
    subject(:result) { activate }

    it_behaves_like "a self-serve entry point"
  end

  it "refuses a user who is not a CS admin", :premium do
    result = activate(current_user: create(:user))

    expect(result["errors"].first["extensions"]["code"]).to eq("unauthorized")
    expect(organization.reload.activation_status).to eq("pending_payment_method")
  end
end
