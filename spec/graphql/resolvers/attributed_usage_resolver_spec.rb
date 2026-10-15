# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::AttributedUsageResolver, clickhouse: {clean_before: true} do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  include_context "with clickhouse availability"

  around { |example| travel_to(Time.zone.parse("2026-09-15 12:00:00")) { example.run } }

  let(:required_permission) { "attributed_usage:view" }
  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["account_tree"]) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: :monthly, amount_currency: "EUR") }
  let(:started_at) { Time.zone.parse("2026-08-01") }
  let(:subscription) { create(:subscription, :calendar, customer:, plan:, started_at:, subscription_at: started_at) }

  let(:tokens_metric) { create(:sum_billable_metric, organization:, code: "tokens", field_name: "tokens") }
  let(:requests_metric) { create(:billable_metric, organization:, code: "requests", aggregation_type: "count_agg") }
  let(:tokens_charge) { create(:standard_charge, plan:, billable_metric: tokens_metric, properties: {"amount" => "0.5"}) }
  let(:requests_charge) { create(:standard_charge, plan:, billable_metric: requests_metric, properties: {"amount" => "2"}) }

  let(:variables) { {subscriptionId: subscription.id, groupBy: "team"} }

  let(:query) do
    <<~GQL
      query(
        $subscriptionId: ID!, $groupBy: String!, $filters: [AttributedUsageFilterInput!], $basis: AttributedUsageBasisEnum,
        $chargeIds: [ID!], $splitChargeId: ID, $fromDatetime: ISO8601DateTime, $toDatetime: ISO8601DateTime,
        $page: Int, $limit: Int, $searchTerm: String
      ) {
        attributedUsage(
          subscriptionId: $subscriptionId, groupBy: $groupBy, filters: $filters, basis: $basis,
          chargeIds: $chargeIds, splitChargeId: $splitChargeId, fromDatetime: $fromDatetime, toDatetime: $toDatetime,
          page: $page, limit: $limit, searchTerm: $searchTerm
        ) {
          subscriptionId externalSubscriptionId groupBy basis currency fromDatetime toDatetime
          rows {
            value rank amountCents preciseAmountCents eventsCount
            chargesUsage { charge { id } chargeFilter { id values } units amountCents preciseAmountCents eventsCount }
          }
          unattributed { amountCents eventsCount }
          totals { amountCents eventsCount }
          metadata { currentPage limitValue totalCount totalPages }
        }
      }
    GQL
  end

  let(:attributed_usage) { result["data"]["attributedUsage"] }

  let(:events) do
    [
      {code: "tokens", value: 1000, labels: {"team" => "eng", "model" => "opus"}, properties: {"model" => "opus"}},
      {code: "tokens", value: 500, labels: {"team" => "eng", "model" => "sonnet"}, properties: {"model" => "sonnet"}},
      {code: "tokens", value: 2000, labels: {"team" => "data", "model" => "opus"}, properties: {"model" => "opus"}},
      {code: "requests", value: 1, labels: {"team" => "eng"}},
      {code: "tokens", value: 100, labels: {}}
    ]
  end

  def create_event(code:, value:, labels:, properties: {})
    Clickhouse::EventsEnriched.create!(
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code:,
      timestamp: Time.zone.parse("2026-09-10"),
      transaction_id: SecureRandom.uuid,
      properties:,
      attribution_labels: labels,
      value: value.to_s,
      decimal_value: value
    )
  end

  def rows_summary
    attributed_usage["rows"].map { it.slice("value", "rank", "eventsCount", "amountCents") }
  end

  before do
    create(:usage_attribution_type, organization:, code: "team")
    create(:flat_usage_attribution_type, organization:, code: "model")
    tokens_charge
    requests_charge
    events.each { create_event(**it) }
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "attributed_usage:view"

  it "returns the attributed usage of the level, in units" do
    expect(attributed_usage).to include(
      "subscriptionId" => subscription.id,
      "externalSubscriptionId" => subscription.external_id,
      "groupBy" => "team",
      "basis" => "units",
      "currency" => "EUR",
      "fromDatetime" => "2026-09-01T00:00:00Z",
      "toDatetime" => "2026-09-30T23:59:59Z"
    )
    expect(rows_summary).to eq(
      [
        {"value" => "eng", "rank" => 1, "eventsCount" => 3, "amountCents" => nil},
        {"value" => "data", "rank" => 2, "eventsCount" => 1, "amountCents" => nil}
      ]
    )
    expect(attributed_usage["rows"].first["chargesUsage"]).to match_array(
      [
        {"charge" => {"id" => tokens_charge.id}, "chargeFilter" => nil, "units" => 1500.0, "amountCents" => nil, "preciseAmountCents" => nil, "eventsCount" => 2},
        {"charge" => {"id" => requests_charge.id}, "chargeFilter" => nil, "units" => 1.0, "amountCents" => nil, "preciseAmountCents" => nil, "eventsCount" => 1}
      ]
    )
    expect(attributed_usage["unattributed"]).to eq("amountCents" => nil, "eventsCount" => 1)
    expect(attributed_usage["totals"]).to eq("amountCents" => nil, "eventsCount" => 5)
    expect(attributed_usage["metadata"]).to eq("currentPage" => 1, "limitValue" => 50, "totalCount" => 2, "totalPages" => 1)
  end

  context "with the amount basis and selected charges" do
    let(:variables) { {subscriptionId: subscription.id, groupBy: "team", basis: "amount", chargeIds: [tokens_charge.id]} }

    it "returns the amounts of the selected charges" do
      expect(rows_summary).to eq(
        [
          {"value" => "data", "rank" => 1, "eventsCount" => 1, "amountCents" => "100000"},
          {"value" => "eng", "rank" => 2, "eventsCount" => 2, "amountCents" => "75000"}
        ]
      )
      expect(attributed_usage["rows"].flat_map { it["chargesUsage"] }.map { it["charge"]["id"] }.uniq).to eq([tokens_charge.id])
      expect(attributed_usage["totals"]).to eq("amountCents" => "180000", "eventsCount" => 4)
    end
  end

  context "with a split charge" do
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric: tokens_metric, key: "model", values: %w[opus sonnet]) }
    let(:charge_filter) { create(:charge_filter, charge: tokens_charge, properties: {"amount" => "1"}) }
    let(:variables) do
      {subscriptionId: subscription.id, groupBy: "team", chargeIds: [tokens_charge.id], splitChargeId: tokens_charge.id}
    end

    before { create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["opus"]) }

    it "returns one charge usage per filter and one for the default price" do
      cells = attributed_usage["rows"].find { it["value"] == "eng" }["chargesUsage"]

      expect(cells.map { [it["chargeFilter"], it["units"]] }).to eq(
        [
          [{"id" => charge_filter.id, "values" => {"model" => ["opus"]}}, 1000.0],
          [nil, 500.0]
        ]
      )
    end
  end

  context "with filters" do
    let(:variables) do
      {subscriptionId: subscription.id, groupBy: "team", filters: [{code: "model", values: %w[opus haiku]}]}
    end

    it "narrows the usage to the matching labels" do
      expect(rows_summary.map { it.slice("value", "eventsCount") }).to eq(
        [{"value" => "data", "eventsCount" => 1}, {"value" => "eng", "eventsCount" => 1}]
      )
    end
  end

  context "with a custom window" do
    let(:variables) do
      {subscriptionId: subscription.id, groupBy: "team", fromDatetime: "2026-09-11T00:00:00Z", toDatetime: "2026-09-14T00:00:00Z"}
    end

    it "reads the window" do
      expect(attributed_usage).to include("fromDatetime" => "2026-09-11T00:00:00Z", "toDatetime" => "2026-09-14T00:00:00Z", "rows" => [])
      expect(attributed_usage["metadata"]).to eq("currentPage" => 1, "limitValue" => 50, "totalCount" => 0, "totalPages" => 0)
    end
  end

  context "with pagination" do
    let(:variables) { {subscriptionId: subscription.id, groupBy: "team", page: 2, limit: 1} }

    it "returns the requested page" do
      expect(rows_summary.map { it.slice("value", "rank") }).to eq([{"value" => "data", "rank" => 2}])
      expect(attributed_usage["metadata"]).to eq("currentPage" => 2, "limitValue" => 1, "totalCount" => 2, "totalPages" => 2)
    end
  end

  context "with an invalid page" do
    let(:variables) { {subscriptionId: subscription.id, groupBy: "team", page: 0} }

    it "returns a validation error" do
      expect_unprocessable_entity(result, details: {page: ["value_is_out_of_range"]})
    end
  end

  context "when the query service rejects the request" do
    let(:variables) { {subscriptionId: subscription.id, groupBy: "team", limit: 101} }

    it "returns its validation error" do
      expect_unprocessable_entity(result, details: {limit: ["value_is_out_of_range"]})
    end
  end

  context "when the query exceeds the ClickHouse limits" do
    before do
      allow(UsageAttributions::QueryService).to receive(:call)
        .and_return(UsageAttributions::QueryService::Result.new.service_failure!(code: "too_many_groups", message: "TOO_MANY_ROWS"))
    end

    it "asks to narrow the request" do
      expect_graphql_error(result:, message: "too_many_groups")
      expect(result["errors"].first["extensions"]).to include("status" => 422, "code" => "too_many_groups")
    end
  end

  context "with a charge outside the plan" do
    let(:variables) { {subscriptionId: subscription.id, groupBy: "team", chargeIds: [tokens_charge.id, create(:standard_charge).id]} }

    it "reads the charges of the plan only" do
      expect(attributed_usage["rows"].flat_map { it["chargesUsage"] }.map { it["charge"]["id"] }.uniq).to eq([tokens_charge.id])
    end
  end

  context "with only charges outside the plan" do
    let(:variables) { {subscriptionId: subscription.id, groupBy: "team", chargeIds: [create(:standard_charge).id]} }

    it "returns a validation error" do
      expect_unprocessable_entity(result, details: {charges: ["must_not_be_empty"]})
    end
  end

  context "with a split charge outside the plan" do
    let(:variables) { {subscriptionId: subscription.id, groupBy: "team", splitChargeId: create(:standard_charge).id} }

    it "does not split any charge" do
      expect(attributed_usage["rows"].flat_map { it["chargesUsage"] }.pluck("chargeFilter").uniq).to eq([nil])
    end
  end

  context "with a terminated subscription" do
    let(:subscription) do
      create(:subscription, :calendar, customer:, plan:, started_at:, subscription_at: started_at,
        status: :terminated, terminated_at: Time.zone.parse("2026-09-12"))
    end

    it "returns a not found error" do
      expect_not_found(result, details: {subscription: ["not_found"]})
    end
  end

  context "with a subscription of another organization" do
    let(:variables) { {subscriptionId: create(:subscription).id, groupBy: "team"} }

    it "returns a not found error" do
      expect_not_found(result, details: {subscription: ["not_found"]})
    end
  end

  context "when the feature flag is disabled" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    it "returns a forbidden error" do
      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end
end
