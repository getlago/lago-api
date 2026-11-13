# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Signups::CreateOrganization do
  subject(:result) { execute_graphql(current_user:, query: mutation, variables: {input:}) }

  include_context "with self-serve enabled"
  include_context "with mocked security logger"

  let(:current_user) { create(:user, :self_serve, email: "jane@getlago.com") }
  let(:input) { {name: "Acme", role: "founder", source: "y_combinator"} }
  let(:mutation) do
    <<~GQL
      mutation($input: CreateSelfServeOrganizationInput!) {
        createSelfServeOrganization(input: $input) {
          productionOrganization { id name environment }
          sandboxOrganization { id name environment }
          landingOrganization { id }
          user { id needsOrganization }
        }
      }
    GQL
  end

  before { create(:role, :admin) }

  it_behaves_like "requires current user"
  it_behaves_like "a self-serve signup step"

  it "creates the pair and lands the user in the sandbox" do
    data = result["data"]["createSelfServeOrganization"]
    production = Organization.find_by!(name: "Acme")
    sandbox = production.sandbox_organization

    expect(data).to eq(
      "productionOrganization" => {"id" => production.id, "name" => "Acme", "environment" => "production"},
      "sandboxOrganization" => {"id" => sandbox.id, "name" => "Acme Sandbox", "environment" => "sandbox"},
      "landingOrganization" => {"id" => sandbox.id},
      "user" => {"id" => current_user.id, "needsOrganization" => false}
    )
  end

  context "without a session" do
    let(:current_user) { nil }

    it "refuses with unauthorized and creates nothing" do
      expect { result }.not_to change(Organization, :count)

      expect(result["errors"].first["extensions"]).to eq("status" => :unauthorized, "code" => "unauthorized")
    end
  end

  context "with a name that carries a link" do
    let(:input) { {name: "acme.com", role: "founder"} }

    it "answers the name error" do
      expect(result["errors"].first["extensions"]).to eq(
        "status" => 422, "code" => "unprocessable_entity", "details" => {"name" => ["value_contains_link"]}
      )
    end
  end

  context "with a user who already has an organization" do
    before { create(:membership, user: current_user) }

    it "refuses with user_not_eligible" do
      expect(result["errors"].first["extensions"]).to eq("status" => 403, "code" => "user_not_eligible")
    end
  end
end
