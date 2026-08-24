# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Subscriptions::HourlyUsageResolver, clickhouse: {clean_before: true}, transaction: false do
  let(:required_permission) { "customers:view" }
  let(:query) do
    <<~GQL
      query($subscriptionId: ID!, $chargeId: ID!, $fromDatetime: ISO8601DateTime, $toDatetime: ISO8601DateTime) {
        subscriptionHourlyUsage(
          subscriptionId: $subscriptionId,
          chargeId: $chargeId,
          fromDatetime: $fromDatetime,
          toDatetime: $toDatetime
        ) {
          fromDatetime
          toDatetime
          timezone
          aggregationType
          lastIngestedAt
          filters { chargeFilterId invoiceDisplayName units eventsCount values }
          hours { time units eventsCount breakdown { chargeFilterId units eventsCount } }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
  let(:charge_filter) { create(:charge_filter, charge:, invoice_display_name: "Europe") }
  let(:charge_filter_value) do
    create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
  end

  let(:from_datetime) { Time.zone.parse("2026-08-24 09:20:00") }
  let(:to_datetime) { Time.zone.parse("2026-08-24 11:05:00") }

  before do
    charge_filter_value

    Clickhouse::UsageBucket.insert_all([
      {
        bucket: Time.zone.parse("2026-08-24 09:30:00"),
        organization_id: organization.id,
        subscription_id: subscription.id,
        customer_id: customer.id,
        plan_id: plan.id,
        code: billable_metric.code,
        charge_id: charge.id,
        charge_filter_id: charge_filter.id,
        grouped_by: "{}",
        aggregation_type: "count",
        events_count: 12,
        units: 12,
        last_event_at: Time.zone.parse("2026-08-24 09:44:00"),
        last_ingested_at: Time.zone.parse("2026-08-24 09:45:12")
      }
    ])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:view"

  it "returns the hourly usage of the charge, broken down by charge filter" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        subscriptionId: subscription.id,
        chargeId: charge.id,
        fromDatetime: from_datetime.iso8601,
        toDatetime: to_datetime.iso8601
      }
    )

    usage = result["data"]["subscriptionHourlyUsage"]

    expect(usage["fromDatetime"]).to eq(Time.zone.parse("2026-08-24 09:00:00").iso8601)
    expect(usage["toDatetime"]).to eq(to_datetime.iso8601)
    expect(usage["timezone"]).to eq("TZ_UTC")
    expect(usage["aggregationType"]).to eq("count_agg")
    expect(usage["lastIngestedAt"]).to eq(Time.zone.parse("2026-08-24 09:45:12").iso8601)

    expect(usage["filters"]).to eq(
      [
        {
          "chargeFilterId" => charge_filter.id,
          "invoiceDisplayName" => "Europe",
          "units" => 12.0,
          "eventsCount" => 12,
          "values" => {"region" => ["eu"]}
        }
      ]
    )

    expect(usage["hours"].map { |hour| hour["time"] }).to eq(
      [
        Time.zone.parse("2026-08-24 09:00:00").iso8601,
        Time.zone.parse("2026-08-24 10:00:00").iso8601,
        Time.zone.parse("2026-08-24 11:00:00").iso8601
      ]
    )
    expect(usage["hours"].map { |hour| hour["units"] }).to eq([12.0, 0.0, 0.0])
    expect(usage["hours"].first["breakdown"]).to eq(
      [{"chargeFilterId" => charge_filter.id, "units" => 12.0, "eventsCount" => 12}]
    )
  end

  it "returns a not found error when the charge does not belong to the subscription plan" do
    other_charge = create(:standard_charge, plan: create(:plan, organization:), billable_metric:)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        subscriptionId: subscription.id,
        chargeId: other_charge.id
      }
    )

    expect_graphql_error(result:, message: "Resource not found")
  end
end
