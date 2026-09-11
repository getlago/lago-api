# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::UsageAttributionTypes::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: usage_attribution_type.id}}
    )
  end

  let(:required_permission) { "usage_attribution_types:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:usage_attribution_type) { create(:usage_attribution_type, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyUsageAttributionTypeInput!) {
        destroyUsageAttributionType(input: $input) { id }
      }
    GQL
  end

  before { organization.update!(feature_flags: ["account_tree"]) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "usage_attribution_types:delete"

  it "discards the usage attribution type" do
    expect { execution }.to change { usage_attribution_type.reload.discarded? }.from(false).to(true)

    expect(execution["data"]["destroyUsageAttributionType"]["id"]).to eq(usage_attribution_type.id)
  end

  context "when the type belongs to another organization" do
    let(:usage_attribution_type) { create(:usage_attribution_type) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  context "when the account_tree feature flag is disabled" do
    before { organization.update!(feature_flags: []) }

    it "returns a forbidden error" do
      expect_graphql_error(result: execution, message: "forbidden")
    end
  end
end
