# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Contracts::Alerts::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: alert.id}}
    )
  end

  let_it_be(:organization, refind: true) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:membership) { create(:membership, organization:) }

  let(:required_permission) { "contracts:update" }
  let(:alert) { create(:contract_alert, organization:) }
  let(:mutation) do
    <<~GQL
      mutation($input: DestroyContractAlertInput!) {
        destroyContractAlert(input: $input) { id deletedAt }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "deletes the alert" do
    freeze_time do
      expect(execution["data"]["destroyContractAlert"]).to eq("id" => alert.id, "deletedAt" => Time.current.iso8601)
      expect(UsageMonitoring::ContractAlert.with_discarded.find(alert.id)).to be_discarded
    end
  end

  context "when the alert belongs to another organization" do
    let(:alert) { create(:contract_alert) }

    it "returns a not found error" do
      expect_not_found(execution, details: {alert: ["not_found"]})
      expect(alert.reload).not_to be_discarded
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first["extensions"]).to eq("status" => 403, "code" => "feature_unavailable")
    end
  end
end
