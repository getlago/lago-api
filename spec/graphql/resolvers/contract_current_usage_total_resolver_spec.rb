# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ContractCurrentUsageTotalResolver do
  around { |example| travel_to(Time.zone.parse("2027-02-10 12:00:00")) { example.run } }

  let_it_be(:organization, refind: true) { create_default(:organization, feature_flags: [:product_catalog]) }
  let_it_be(:membership, refind: true) { create_default(:membership) }
  let(:required_permission) { "contracts:view" }
  let(:contract) { create(:contract, organization:, customer: create(:customer, organization:)) }

  let(:query) do
    <<~GQL
      query($contractId: ID!) {
        contractCurrentUsageTotal(contractId: $contractId) {
          amountCents
          taxesAmountCents
          totalAmountCents
          taxesUnavailable
          fromDatetime
          toDatetime
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:view"

  it "returns zero totals for a contract with no usage" do
    result = execute_graphql(
      current_user: membership.user, current_organization: organization,
      permissions: required_permission, query:, variables: {contractId: contract.id}
    )

    totals = result["data"]["contractCurrentUsageTotal"]
    expect(totals).to eq(
      "amountCents" => "0", "taxesAmountCents" => "0", "totalAmountCents" => "0", "taxesUnavailable" => false,
      "fromDatetime" => nil, "toDatetime" => nil
    )
  end

  context "with a priced rate card" do
    let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
    let(:product) { create(:product, :standalone, :metered, organization:, billable_metric:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: :arrears, currency: "EUR") }
    let(:billing_scope) { "cycle" }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:,
        effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1), billing_scope:)
    end
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
        rate_properties: {"amount" => "2"})
    end

    before do
      contract_rate_card
      rate
      [Time.zone.parse("2027-01-10"), Time.zone.parse("2027-02-05")].each do |event_timestamp|
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: event_timestamp)
      end
    end

    it "returns the contract's total current usage" do
      result = execute_graphql(
        current_user: membership.user, current_organization: organization,
        permissions: required_permission, query:, variables: {contractId: contract.id}
      )

      totals = result["data"]["contractCurrentUsageTotal"]
      expect(totals).to eq(
        "amountCents" => "200", "taxesAmountCents" => "0", "totalAmountCents" => "200", "taxesUnavailable" => false,
        "fromDatetime" => "2027-02-01T00:00:00Z", "toDatetime" => "2027-02-28T23:59:59Z"
      )
    end

    context "with a midcycle rate change" do
      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-07"),
          rate_properties: {"amount" => "5"})
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: Time.zone.parse("2027-02-08"))
      end

      shared_examples "returns the selected obligation total" do
        it "reports its complete window and total" do
          result = execute_graphql(
            current_user: membership.user, current_organization: organization,
            permissions: required_permission, query:, variables: {contractId: contract.id}
          )

          expect(result["data"]["contractCurrentUsageTotal"]).to eq(
            "amountCents" => expected_amount, "taxesAmountCents" => "0", "totalAmountCents" => expected_amount,
            "taxesUnavailable" => false, "fromDatetime" => expected_start, "toDatetime" => "2027-02-28T23:59:59Z"
          )
        end
      end

      context "with cycle scope" do
        let(:expected_start) { "2027-02-01T00:00:00Z" }
        let(:expected_amount) { "700" } # One event at 2 EUR and one at 5 EUR.

        include_examples "returns the selected obligation total"
      end

      context "with segment scope" do
        let(:billing_scope) { "segment" }
        let(:expected_start) { "2027-02-07T00:00:00Z" }
        let(:expected_amount) { "500" }

        include_examples "returns the selected obligation total"
      end
    end

    context "with rate cards in and out of a product category" do
      let(:query) do
        <<~GQL
          query($contractId: ID!) {
            contractCurrentUsageTotal(contractId: $contractId) {
              amountCents
              taxesAmountCents
              totalAmountCents
              productCategoryTotals {
                productCategory { id name }
                amountCents
                taxesAmountCents
                totalAmountCents
                fromDatetime
                toDatetime
              }
            }
          }
        GQL
      end
      let(:product_category) { create(:product_category, organization:, name: "Compute") }
      let(:category_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
      let(:category_product) do
        create(:product, :metered, organization:, product_category:, billable_metric: category_metric)
      end
      let(:category_rate_card) do
        create(:rate_card, organization:, product: category_product, billing_timing: :arrears, currency: "EUR")
      end
      let(:second_category_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
      let(:second_category_product) do
        create(:product, :metered, organization:, product_category:, billable_metric: second_category_metric)
      end
      let(:second_category_rate_card) do
        create(:rate_card, organization:, product: second_category_product, billing_timing: :arrears, currency: "EUR")
      end

      before do
        create(:contract_rate_card, organization:, contract:, rate_card: category_rate_card,
          effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 15))
        create(:rate_card_rate, organization:, rate_card: category_rate_card,
          effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "3"})
        create(:rate_card_applied_tax, rate_card: category_rate_card, tax: create(:tax, organization:, rate: 20))
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: category_metric.code, timestamp: Time.zone.parse("2027-02-05"))

        create(:contract_rate_card, organization:, contract:, rate_card: second_category_rate_card,
          effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 2, 3))
        create(:rate_card_rate, organization:, rate_card: second_category_rate_card,
          effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "4"})
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: second_category_metric.code, timestamp: Time.zone.parse("2027-02-05"))
      end

      it "splits the total by product category, summing each category's rate cards, taxes and windows" do
        result = execute_graphql(
          current_user: membership.user, current_organization: organization,
          permissions: required_permission, query:, variables: {contractId: contract.id}
        )

        totals = result["data"]["contractCurrentUsageTotal"]
        expect(totals).to include("amountCents" => "900", "taxesAmountCents" => "60", "totalAmountCents" => "960")
        expect(totals["productCategoryTotals"]).to contain_exactly(
          {
            "productCategory" => nil,
            "amountCents" => "200", "taxesAmountCents" => "0", "totalAmountCents" => "200",
            "fromDatetime" => "2027-02-01T00:00:00Z", "toDatetime" => "2027-02-28T23:59:59Z"
          },
          {
            "productCategory" => {"id" => product_category.id, "name" => "Compute"},
            "amountCents" => "700", "taxesAmountCents" => "60", "totalAmountCents" => "760",
            "fromDatetime" => "2027-01-15T00:00:00Z", "toDatetime" => "2027-03-02T23:59:59Z"
          }
        )
      end
    end

    context "when the tax provider fails" do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:endpoint) { "https://api.nango.dev/action/trigger" }

      before do
        create(:anrok_customer, integration:, customer:)
        create(:netsuite_collection_mapping, integration:, mapping_type: :fallback_item,
          settings: {external_id: "1", external_account_code: "11", external_name: ""})
        create(:rate_card_applied_tax, rate_card:, tax: create(:tax, organization:, rate: 20))
        stub_request(:post, endpoint).to_raise(Net::ReadTimeout)
      end

      it "falls back to the untaxed total instead of failing the whole query" do
        result = execute_graphql(
          current_user: membership.user, current_organization: organization,
          permissions: required_permission, query:, variables: {contractId: contract.id}
        )

        totals = result["data"]["contractCurrentUsageTotal"]
        expect(totals).to eq(
          "amountCents" => "200", "taxesAmountCents" => "0", "totalAmountCents" => "200", "taxesUnavailable" => true,
          "fromDatetime" => "2027-02-01T00:00:00Z", "toDatetime" => "2027-02-28T23:59:59Z"
        )
        expect(WebMock).to have_requested(:post, endpoint).once
      end

      context "when the provider throttles the request" do
        before do
          allow(Throttling).to receive(:for).with(:anrok).and_return(instance_double(Throttling::Base, check: false))
        end

        it "falls back to the untaxed total" do
          result = execute_graphql(
            current_user: membership.user, current_organization: organization,
            permissions: required_permission, query:, variables: {contractId: contract.id}
          )

          totals = result["data"]["contractCurrentUsageTotal"]
          expect(totals).to include("amountCents" => "200", "totalAmountCents" => "200", "taxesUnavailable" => true)
        end
      end
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
