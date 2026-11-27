# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Contracts::AlertResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {id: alert_id}
    )
  end

  let_it_be(:organization, refind: true) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:membership) { create(:membership, organization:) }
  let_it_be(:product) { create(:product, organization:) }
  let_it_be(:product_filter) { create(:product_filter, organization:, product:) }
  let_it_be(:alert) do
    create(
      :contract_usage_units_alert,
      organization:,
      product:,
      product_filter:,
      name: "Opus tokens",
      previous_value: 1_200_000,
      last_processed_at: Time.zone.parse("2026-11-18T10:00:00Z"),
      thresholds: [2_000_000, 1_000_000],
      recurring_threshold: 500_000
    )
  end

  let(:required_permission) { "contracts:view" }
  let(:alert_id) { alert.id }
  let(:query) do
    <<~GQL
      query($id: ID!) {
        contractAlert(id: $id) {
          id alertType code name direction contractExternalId
          scope { type product { id code } productFilters { id code } withProductFilters }
          thresholds { code value recurring notifyOn }
          previousValue lastProcessedAt createdAt updatedAt deletedAt
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:view"

  it "returns the alert" do
    expect(execution["data"]["contractAlert"]).to eq(
      "id" => alert.id,
      "alertType" => "usage_units",
      "code" => alert.code,
      "name" => "Opus tokens",
      "direction" => "increasing",
      "contractExternalId" => alert.contract_external_id,
      "scope" => [
        {
          "type" => "contract",
          "product" => {"id" => product.id, "code" => product.code},
          "productFilters" => [{"id" => product_filter.id, "code" => product_filter.code}],
          "withProductFilters" => nil
        }
      ],
      "thresholds" => [
        {"code" => "warn1000000", "value" => "1000000.0", "recurring" => false, "notifyOn" => ["triggered"]},
        {"code" => "warn2000000", "value" => "2000000.0", "recurring" => false, "notifyOn" => ["triggered"]},
        {"code" => "rec", "value" => "500000.0", "recurring" => true, "notifyOn" => ["triggered"]}
      ],
      "previousValue" => "1200000.0",
      "lastProcessedAt" => "2026-11-18T10:00:00Z",
      "createdAt" => alert.created_at.iso8601,
      "updatedAt" => alert.updated_at.iso8601,
      "deletedAt" => nil
    )
  end

  context "when the alert belongs to another organization" do
    let(:alert_id) { create(:contract_alert).id }

    it "returns a not found error" do
      expect_not_found(execution, details: {alert: ["not_found"]})
    end
  end

  context "when the alert is deleted" do
    let(:alert_id) { create(:contract_alert, organization:, deleted_at: Time.current).id }

    it "returns a not found error" do
      expect_not_found(execution, details: {alert: ["not_found"]})
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first["extensions"]).to eq("status" => 403, "code" => "feature_unavailable")
    end
  end
end
