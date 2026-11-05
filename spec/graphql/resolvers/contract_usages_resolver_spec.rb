# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ContractUsagesResolver do
  around { |example| travel_to(Time.zone.parse("2027-02-10 12:00:00")) { example.run } }

  let_it_be(:organization, refind: true) { create_default(:organization, feature_flags: [:product_catalog]) }
  let_it_be(:membership, refind: true) { create_default(:membership) }
  let(:required_permission) { "contracts:view" }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
  let(:product) { create(:product, :standalone, :metered, organization:, billable_metric:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: :arrears, currency: "EUR") }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
  end
  let(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
      rate_properties: {"amount" => "2"})
  end

  let(:query) do
    <<~GQL
      query($contractId: ID!, $withoutProductCategory: Boolean) {
        contractUsages(contractId: $contractId, withoutProductCategory: $withoutProductCategory) {
          collection { rateCardCode productName units amountCents }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:view"

  context "with a priced rate card" do
    before do
      contract_rate_card
      rate
      [Time.zone.parse("2027-01-10"), Time.zone.parse("2027-02-05")].each do |event_timestamp|
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: event_timestamp)
      end
    end

    it "returns the contract's rate card usage" do
      result = execute_graphql(
        current_user: membership.user, current_organization: organization,
        permissions: required_permission, query:,
        variables: {contractId: contract.id, withoutProductCategory: true}
      )

      collection = result["data"]["contractUsages"]["collection"]
      expect(collection.sole).to include("rateCardCode" => rate_card.code, "productName" => product.name, "units" => 1.0, "amountCents" => "200")
    end

    context "with page beyond the available rows" do
      let(:query) do
        <<~GQL
          query($contractId: ID!, $page: Int) {
            contractUsages(contractId: $contractId, page: $page) {
              collection { rateCardCode }
              metadata { currentPage totalCount }
            }
          }
        GQL
      end

      it "returns an empty collection, not an out-of-range error" do
        result = execute_graphql(
          current_user: membership.user, current_organization: organization,
          permissions: required_permission, query:,
          variables: {contractId: contract.id, page: 5}
        )

        expect(result["data"]["contractUsages"]["collection"]).to eq([])
        expect(result["data"]["contractUsages"]["metadata"]["totalCount"]).to eq(1)
      end
    end

    context "with withoutProductFilter (the \"Not defined\" option)" do
      let(:query) do
        <<~GQL
          query($contractId: ID!, $withoutProductFilter: Boolean) {
            contractUsages(contractId: $contractId, withoutProductFilter: $withoutProductFilter) {
              collection { rateCardCode }
            }
          }
        GQL
      end

      it "matches rate cards with no product filter" do
        result = execute_graphql(
          current_user: membership.user, current_organization: organization,
          permissions: required_permission, query:,
          variables: {contractId: contract.id, withoutProductFilter: true}
        )

        expect(result["data"]["contractUsages"]["collection"].sole["rateCardCode"]).to eq(rate_card.code)
      end
    end
  end

  context "with a contract that has no usage" do
    it "returns an empty collection, not an error" do
      result = execute_graphql(
        current_user: membership.user, current_organization: organization,
        permissions: required_permission, query:, variables: {contractId: contract.id}
      )

      expect(result["data"]["contractUsages"]["collection"]).to eq([])
      expect(result["data"]["contractUsages"]["metadata"]["totalCount"]).to eq(0)
    end
  end

  context "when the contract belongs to another organization" do
    let(:contract) { create(:contract, organization: create(:organization)) }

    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user, current_organization: organization,
        permissions: required_permission, query:, variables: {contractId: contract.id}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
