# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Contracts::AlertsResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {contractId: contract_id, page:, limit:}
    )
  end

  let_it_be(:organization, refind: true) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:membership) { create(:membership, organization:) }
  let_it_be(:contract) { create(:contract, organization:, customer: create(:customer, organization:)) }
  let_it_be(:older_alert) do
    create(:contract_usage_amount_alert, organization:, contract_external_id: contract.external_id, created_at: 2.days.ago)
  end
  let_it_be(:newer_alert) do
    create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id, created_at: 1.day.ago)
  end

  let(:required_permission) { "contracts:view" }
  let(:contract_id) { contract.id }
  let(:page) { nil }
  let(:limit) { nil }
  let(:query) do
    <<~GQL
      query($contractId: ID!, $page: Int, $limit: Int) {
        contractAlerts(contractId: $contractId, page: $page, limit: $limit) {
          collection { id code scope { product { id } productFilters { id } withProductFilters } thresholds { value } }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  before_all do
    create(:contract_alert, organization:)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:view"

  it "returns the alerts on the contract external id, newest first" do
    response = execution["data"]["contractAlerts"]

    expect(response["collection"]).to eq([
      {
        "id" => newer_alert.id,
        "code" => newer_alert.code,
        "scope" => [{"product" => {"id" => newer_alert.product_id}, "productFilters" => nil, "withProductFilters" => false}],
        "thresholds" => [{"value" => "1500.0"}]
      },
      {
        "id" => older_alert.id,
        "code" => older_alert.code,
        "scope" => [],
        "thresholds" => [{"value" => "1500.0"}]
      }
    ])
    expect(response["metadata"]).to eq("currentPage" => 1, "totalCount" => 2)
  end

  it "does not trigger N+1 queries", :bullet do
    product = create(:product, organization:)
    create(
      :contract_usage_units_alert,
      organization:,
      contract_external_id: contract.external_id,
      product:,
      product_filter: create(:product_filter, organization:, product:)
    )

    expect(execution["data"]["contractAlerts"]["collection"].size).to eq(3)
  end

  context "with pagination" do
    let(:page) { 2 }
    let(:limit) { 1 }

    it "returns the requested page" do
      response = execution["data"]["contractAlerts"]

      expect(response["collection"].pluck("id")).to eq([older_alert.id])
      expect(response["metadata"]).to eq("currentPage" => 2, "totalCount" => 2)
    end
  end

  context "with a terminated contract on the external id" do
    let(:contract_id) do
      create(:contract, :terminated, organization:, customer: contract.customer, external_id: contract.external_id).id
    end

    it "returns the alerts on its external id" do
      expect(execution["data"]["contractAlerts"]["collection"].pluck("id")).to eq([newer_alert.id, older_alert.id])
    end
  end

  context "when the contract belongs to another organization" do
    let(:contract_id) { create(:contract).id }

    it "returns a not found error" do
      expect_not_found(execution, details: {contract: ["not_found"]})
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first["extensions"]).to eq("status" => 403, "code" => "feature_unavailable")
    end
  end
end
