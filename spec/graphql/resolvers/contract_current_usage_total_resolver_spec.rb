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
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:,
        effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
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
