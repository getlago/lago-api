# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomerPortal::Customers::ProjectedUsageResolver do
  let(:query) do
    <<~GQL
      query($subscriptionId: ID!) {
        customerPortalCustomerProjectedUsage(subscriptionId: $subscriptionId) {
          fromDatetime
          toDatetime
          currency
          issuingDate
          amountCents
          projectedAmountCents
          totalAmountCents
          taxesAmountCents
          chargesUsage {
            billableMetric { name code aggregationType }
            charge { chargeModel }
            filters { id units amountCents pricingUnitAmountCents invoiceDisplayName values eventsCount }
            units
            projectedUnits
            amountCents
            projectedAmountCents
            pricingUnitAmountCents
            pricingUnitProjectedAmountCents
            groupedUsage {
              amountCents
              projectedAmountCents
              units
              projectedUnits
              eventsCount
              groupedBy
              filters { id units amountCents pricingUnitAmountCents invoiceDisplayName values eventsCount }
            }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:, rate: 20) }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) do
    create(
      :subscription,
      plan:,
      customer:,
      started_at: Time.zone.now - 2.years
    )
  end
  let(:plan) { create(:plan, interval: "monthly") }

  let(:metric) { create(:billable_metric, aggregation_type: "count_agg") }
  let(:sum_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) do
    create(
      :graduated_charge,
      plan: subscription.plan,
      charge_model: "graduated",
      billable_metric: metric,
      properties: {
        graduated_ranges: [
          {
            from_value: 0,
            to_value: nil,
            per_unit_amount: "0.01",
            flat_amount: "0.01"
          }
        ]
      }
    )
  end
  let(:standard_charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      billable_metric: sum_metric,
      properties: {
        amount: 1.to_s,
        grouped_by: ["agent_name"]
      }
    )
  end

  let(:billable_metric_filter) do
    create(:billable_metric_filter, billable_metric: metric, key: "cloud", values: %w[aws gcp])
  end

  let(:charge_filter) { create(:charge_filter, charge: standard_charge, invoice_display_name: nil) }
  let(:charge_filter_value) do
    create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["aws"])
  end

  before do
    subscription
    charge
    tax
    charge_filter_value

    create(
      :applied_pricing_unit,
      organization: organization,
      conversion_rate: 0.25,
      pricing_unitable: standard_charge
    )

    travel_to(Time.parse("2025-07-15T10:00:00Z")) do
      create_list(
        :event,
        4,
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now
      )

      create_list(
        :event,
        4,
        organization:,
        customer:,
        subscription:,
        code: sum_metric.code,
        timestamp: Time.zone.now,
        properties: {
          agent_name: "frodo",
          cloud: "aws",
          item_id: 1
        }
      )
    end
  end

  it_behaves_like "requires a customer portal user"

  it "returns the projected usage for the customer" do
    travel_to(Time.parse("2025-07-15T10:00:00Z")) do
      result = execute_graphql(
        customer_portal_user: customer,
        query:,
        variables: {
          subscriptionId: subscription.id
        }
      )

      # debugger
      usage_response = result["data"]["customerPortalCustomerProjectedUsage"]

      aggregate_failures do
        expect(usage_response["fromDatetime"]).to eq(Time.current.beginning_of_month.iso8601)
        expect(usage_response["toDatetime"]).to eq(Time.current.end_of_month.iso8601)
        expect(usage_response["currency"]).to eq("EUR")
        expect(usage_response["issuingDate"]).to eq(Time.zone.today.end_of_month.iso8601)
        expect(usage_response["amountCents"]).to eq("105")
        expect(usage_response["projectedAmountCents"]).to eq("836")
        expect(usage_response["totalAmountCents"]).to eq("105")
        expect(usage_response["taxesAmountCents"]).to eq("0")

        charge_usage = usage_response["chargesUsage"].find { it["billableMetric"]["code"] == metric.code }
        expect(charge_usage["billableMetric"]["name"]).to eq(metric.name)
        expect(charge_usage["billableMetric"]["aggregationType"]).to eq("count_agg")
        expect(charge_usage["charge"]["chargeModel"]).to eq("graduated")
        expect(charge_usage["pricingUnitAmountCents"]).to eq(nil)
        expect(charge_usage["units"]).to eq(4.0)
        expect(charge_usage["projectedUnits"]).to eq(8.27)
        expect(charge_usage["amountCents"]).to eq("5")
        expect(charge_usage["projectedAmountCents"]).to eq("9")

        charge_usage = usage_response["chargesUsage"].find { it["billableMetric"]["code"] == sum_metric.code }
        expect(charge_usage["billableMetric"]["name"]).to eq(sum_metric.name)
        expect(charge_usage["billableMetric"]["aggregationType"]).to eq("sum_agg")
        expect(charge_usage["charge"]["chargeModel"]).to eq("standard")
        expect(charge_usage["pricingUnitAmountCents"]).to eq("400")
        expect(charge_usage["pricingUnitProjectedAmountCents"]).to eq("207")
        expect(charge_usage["units"]).to eq(4.0)
        expect(charge_usage["projectedUnits"]).to eq(8.27)
        expect(charge_usage["amountCents"]).to eq("100")
        expect(charge_usage["projectedAmountCents"]).to eq("827")

        grouped_usage = charge_usage["groupedUsage"].first
        expect(grouped_usage["amountCents"]).to eq("100")
        expect(grouped_usage["projectedAmountCents"]).to eq("827")
        expect(grouped_usage["units"]).to eq(4.0)
        expect(grouped_usage["projectedUnits"]).to eq(8.27)
        expect(grouped_usage["eventsCount"]).to eq(4)
        expect(grouped_usage["groupedBy"]).to eq({"agent_name" => "frodo"})
      end
    end
  end

  context "with filters" do
    let(:filter_metric) { create(:billable_metric, aggregation_type: "count_agg", organization:) }
    let(:cloud_bm_filter) do
      create(:billable_metric_filter, billable_metric: filter_metric, key: "cloud", values: %w[aws google])
    end

    let(:aws_filter) do
      create(:charge_filter, charge:, properties: {amount: "10"})
    end
    let(:aws_filter_value) do
      create(:charge_filter_value, charge_filter: aws_filter, billable_metric_filter: cloud_bm_filter, values: ["aws"])
    end

    let(:google_filter) do
      create(:charge_filter, charge:, properties: {amount: "20"})
    end
    let(:google_filter_value) do
      create(
        :charge_filter_value,
        charge_filter: google_filter,
        billable_metric_filter: cloud_bm_filter,
        values: ["google"]
      )
    end

    let(:charge) do
      create(
        :standard_charge,
        plan: subscription.plan,
        billable_metric: filter_metric,
        properties: {amount: "0"}
      )
    end

    before do
      subscription
      charge
      tax
      aws_filter_value
      google_filter_value

      create(
        :applied_pricing_unit,
        organization: organization,
        conversion_rate: 0.2,
        pricing_unitable: charge
      )

      travel_to(Time.parse("2025-07-15T10:00:00Z")) do
        create_list(
          :event,
          3,
          organization:,
          customer:,
          subscription:,
          code: filter_metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: "aws"}
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: filter_metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: "google"}
        )
      end
    end

    it "returns the projected filter usage for the customer" do
      travel_to(Time.parse("2025-07-15T10:00:00Z")) do
        result = execute_graphql(
          customer_portal_user: customer,
          query:,
          variables: {
            subscriptionId: subscription.id
          }
        )

        charge_usage = result["data"]["customerPortalCustomerProjectedUsage"]["chargesUsage"].find do |usage|
          usage["billableMetric"]["code"] == filter_metric.code
        end

        filters_usage = charge_usage["filters"]

        aggregate_failures do
          expect(charge_usage["units"]).to eq(4)
          expect(charge_usage["amountCents"]).to eq("1000")
          expect(charge_usage["projectedUnits"]).to eq(8.27)
          expect(charge_usage["projectedAmountCents"]).to eq("10340")

          aws_filter_data = filters_usage.find { |f| f["id"] == aws_filter.id }
          expect(aws_filter_data["units"]).to eq(3)
          expect(aws_filter_data["amountCents"]).to eq("600")
          expect(aws_filter_data["pricingUnitAmountCents"]).to eq("3000")

          google_filter_data = filters_usage.find { |f| f["id"] == google_filter.id }
          expect(google_filter_data["units"]).to eq(1)
          expect(google_filter_data["amountCents"]).to eq("400")
          expect(google_filter_data["pricingUnitAmountCents"]).to eq("2000")
        end
      end
    end
  end
end
