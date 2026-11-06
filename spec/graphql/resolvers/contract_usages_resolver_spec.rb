# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ContractUsagesResolver do
  around { |example| travel_to(Time.zone.parse("2027-02-10 12:00:00")) { example.run } }

  let_it_be(:organization, refind: true) { create_default(:organization, feature_flags: [:product_catalog]) }
  let_it_be(:membership, refind: true) { create_default(:membership) }
  let(:required_permission) { "contracts:view" }
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

  # A second, differently-scoped card - referenced only by tests that need to prove a filter
  # argument actually reaches the service and excludes it, not just that the matching card appears.
  let(:categorized_product) { create(:product, organization:, billable_metric: create(:billable_metric, organization:)) }
  let(:categorized_rate_card) { create(:rate_card, organization:, product: categorized_product, currency: "EUR") }
  let(:categorized_contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card: categorized_rate_card,
      effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
  end

  def create_excluded_card
    categorized_contract_rate_card
    create(:rate_card_rate, organization:, rate_card: categorized_rate_card,
      effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "9"})
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

    it "excludes a categorized card when withoutProductCategory is true, proving the argument reaches the service" do
      create_excluded_card

      result = execute_graphql(
        current_user: membership.user, current_organization: organization,
        permissions: required_permission, query:,
        variables: {contractId: contract.id, withoutProductCategory: true}
      )

      expect(result["data"]["contractUsages"]["collection"].sole["rateCardCode"]).to eq(rate_card.code)
    end

    context "with searchTerm" do
      let(:query) do
        <<~GQL
          query($contractId: ID!, $searchTerm: String) {
            contractUsages(contractId: $contractId, searchTerm: $searchTerm) {
              collection { rateCardCode }
            }
          }
        GQL
      end

      it "matches on product name and excludes non-matching cards" do
        create_excluded_card

        result = execute_graphql(
          current_user: membership.user, current_organization: organization,
          permissions: required_permission, query:,
          variables: {contractId: contract.id, searchTerm: product.name}
        )

        expect(result["data"]["contractUsages"]["collection"].sole["rateCardCode"]).to eq(rate_card.code)
      end
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

    context "with page 0" do
      let(:query) do
        <<~GQL
          query($contractId: ID!, $page: Int) {
            contractUsages(contractId: $contractId, page: $page) {
              collection { rateCardCode }
            }
          }
        GQL
      end

      it "returns a validation error instead of a negative-offset slice" do
        result = execute_graphql(
          current_user: membership.user, current_organization: organization,
          permissions: required_permission, query:,
          variables: {contractId: contract.id, page: 0}
        )

        expect_graphql_error(result:, message: "Unprocessable Entity")
      end
    end

    context "with a non-positive limit" do
      let(:query) do
        <<~GQL
          query($contractId: ID!, $limit: Int) {
            contractUsages(contractId: $contractId, limit: $limit) {
              collection { rateCardCode }
            }
          }
        GQL
      end

      it "returns a validation error instead of crashing" do
        result = execute_graphql(
          current_user: membership.user, current_organization: organization,
          permissions: required_permission, query:,
          variables: {contractId: contract.id, limit: 0}
        )

        expect_graphql_error(result:, message: "Unprocessable Entity")
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

      it "matches rate cards with no product filter, excluding a filtered one" do
        product_filter = create(:product_filter, organization:, product: categorized_product)
        filtered_rate_card = create(:rate_card, organization:, product: categorized_product, product_filter:, currency: "EUR")
        create(:contract_rate_card, organization:, contract:, rate_card: filtered_rate_card,
          effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
        create(:rate_card_rate, organization:, rate_card: filtered_rate_card,
          effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "9"})

        result = execute_graphql(
          current_user: membership.user, current_organization: organization,
          permissions: required_permission, query:,
          variables: {contractId: contract.id, withoutProductFilter: true}
        )

        expect(result["data"]["contractUsages"]["collection"].sole["rateCardCode"]).to eq(rate_card.code)
      end
    end
  end

  context "with a product's filter card chronologically split from its own unfiltered card by another product" do
    let(:eu_filter) { create(:product_filter, organization:, product:) }
    let(:filtered_rate_card) { create(:rate_card, organization:, product:, product_filter: eu_filter, currency: "EUR") }

    let(:query) do
      <<~GQL
        query($contractId: ID!) {
          contractUsages(contractId: $contractId) {
            collection { rateCardCode }
          }
        }
      GQL
    end

    before do
      region = create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us])
      create(:product_filter_value, organization:, product_filter: eu_filter, billable_metric_filter: region, value: "eu")

      # Windows chronologically interleave B between A's two cards (Feb1, Feb5, Feb8) so a plain
      # chronological sort would place B between them - proving grouping, not luck, keeps them adjacent.
      contract_rate_card
      rate

      create(:contract_rate_card, organization:, contract:, rate_card: filtered_rate_card,
        effective_date: Date.new(2027, 2, 1), billing_anchor_date: Date.new(2027, 2, 1))
      create(:rate_card_rate, organization:, rate_card: filtered_rate_card, billing_interval_unit: "week",
        effective_from: Time.zone.parse("2027-02-01"), rate_properties: {"amount" => "9"})

      create(:contract_rate_card, organization:, contract:, rate_card: categorized_rate_card,
        effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
      create(:rate_card_rate, organization:, rate_card: categorized_rate_card, billing_interval_unit: "week",
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "5"})
    end

    it "keeps the unfiltered card and its filter card adjacent, unfiltered first" do
      result = execute_graphql(
        current_user: membership.user, current_organization: organization,
        permissions: required_permission, query:,
        variables: {contractId: contract.id}
      )

      codes = result["data"]["contractUsages"]["collection"].map { |row| row["rateCardCode"] }
      expect(codes.size).to eq(3)

      unfiltered_index = codes.index(rate_card.code)
      filtered_index = codes.index(filtered_rate_card.code)

      expect(filtered_index).to eq(unfiltered_index + 1)
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
