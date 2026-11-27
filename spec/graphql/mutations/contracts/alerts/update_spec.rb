# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Contracts::Alerts::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let_it_be(:organization, refind: true) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:membership) { create(:membership, organization:) }
  let_it_be(:customer) { create(:customer, organization:) }

  let(:required_permission) { "contracts:update" }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:alert) do
    create(:contract_usage_amount_alert, organization:, contract_external_id: contract.external_id, name: "Spend", thresholds: [1000])
  end
  let(:input) do
    {
      id: alert.id,
      name: "Monthly spend",
      thresholds: [
        {code: "warn", value: "2000", notifyOn: %w[triggered resolved]},
        {value: "500", recurring: true}
      ]
    }
  end
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateContractAlertInput!) {
        updateContractAlert(input: $input) {
          id name
          thresholds { code value recurring notifyOn }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "updates the name and replaces the thresholds" do
    response = execution["data"]["updateContractAlert"]

    expect(response).to eq(
      "id" => alert.id,
      "name" => "Monthly spend",
      "thresholds" => [
        {"code" => "warn", "value" => "2000.0", "recurring" => false, "notifyOn" => %w[triggered resolved]},
        {"code" => nil, "value" => "500.0", "recurring" => true, "notifyOn" => ["triggered"]}
      ]
    )
    expect(alert.reload.name).to eq("Monthly spend")
  end

  context "with only the name" do
    let(:input) { {id: alert.id, name: "Monthly spend"} }

    it "keeps the thresholds" do
      response = execution["data"]["updateContractAlert"]

      expect(response["name"]).to eq("Monthly spend")
      expect(response["thresholds"]).to eq([
        {"code" => "warn1000", "value" => "1000.0", "recurring" => false, "notifyOn" => ["triggered"]}
      ])
    end
  end

  [nil, []].each do |thresholds|
    context "with thresholds #{thresholds.inspect}" do
      let(:input) { {id: alert.id, thresholds:} }

      it "returns a validation error and keeps the thresholds" do
        expect_unprocessable_entity(execution, details: {thresholds: ["value_is_mandatory"]})
        expect(alert.reload.thresholds.pluck(:value)).to eq([1000])
      end
    end
  end

  context "when the alert belongs to another organization" do
    let(:alert) { create(:contract_alert) }

    it "returns a not found error" do
      expect_not_found(execution, details: {alert: ["not_found"]})
    end
  end

  context "when no contract on the external id is pending or active" do
    let(:contract) { create(:contract, :terminated, organization:, customer:) }

    it "returns a contract not live error" do
      expect(execution["errors"].first["extensions"]).to eq("status" => 403, "code" => "contract_not_live")
      expect(alert.reload.name).to eq("Spend")
    end
  end

  context "with a threshold value that is not a number" do
    let(:input) { {id: alert.id, thresholds: [{value: "abc"}]} }

    it "returns a validation error on its value" do
      expect_unprocessable_entity(execution, details: {"thresholds[0].value": ["value_is_invalid"]})
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first["extensions"]).to eq("status" => 403, "code" => "feature_unavailable")
    end
  end
end
