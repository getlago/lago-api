# frozen_string_literal: true

require "rails_helper"

# Regression tests for overlapping charge filters on the same charge:
# - ISSUE-1799: filters with no values produce empty hashes in ignored_filters;
#   the store-level defensive guards prevent them from rendering invalid SQL.
# - Subset and identical duplicate filters used to be double-counted: events
#   matching both a filter and a more specific sibling were counted in both
#   buckets. Each event must only be counted in its most specific bucket.
describe "Current Usage - Overlapping charge filters", transaction: false do
  [
    :postgres,
    :clickhouse
  ].each do |store|
    context "with #{store} store", clickhouse: store == :clickhouse do
      let(:organization) { create(:organization, webhook_url: nil, clickhouse_events_store: store == :clickhouse) }
      let(:customer) { create(:customer, organization:) }
      let(:plan) { create(:plan, organization:, amount_cents: 0, pay_in_advance: false, interval: "monthly") }
      let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }

      # Filters with no ChargeFilterValue records should not exist but can due
      # to missing validations. They produce {} in ignored_filters.
      context "when charge filters have no values" do
        before do
          cloud_filter = create(:billable_metric_filter, billable_metric:, key: "cloud", values: %w[aws gcp])

          charge = create(:standard_charge, plan:, billable_metric:, properties: {amount: "10"})

          create(:charge_filter, charge:, properties: {amount: "5"}, invoice_display_name: "Empty A")
          create(:charge_filter, charge:, properties: {amount: "8"}, invoice_display_name: "Empty B")
          create(:charge_filter, charge:, properties: {amount: "3"}, invoice_display_name: "AWS")
            .tap { |cf| create(:charge_filter_value, charge_filter: cf, billable_metric_filter: cloud_filter, values: ["aws"]) }
        end

        it "returns current usage without SQL errors" do
          travel_to(DateTime.new(2024, 3, 5)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code
              }
            )
          end

          travel_to(DateTime.new(2024, 3, 6)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: customer.external_id,
                properties: {cloud: "aws", value: 10}
              }
            )

            fetch_current_usage(customer:)

            expect(json[:customer_usage][:charges_usage].first[:filters].count).to eq(4)
          end
        end
      end

      # When a child filter's values are a subset of another filter's values,
      # the child is kept verbatim in the parent's ignored_filters, so events
      # matching the child are only counted in the child's bucket.
      context "when a child filter's values are a subset of the parent's" do
        before do
          cloud_filter = create(:billable_metric_filter, billable_metric:, key: "cloud", values: %w[aws gcp])

          charge = create(:standard_charge, plan:, billable_metric:, properties: {amount: "10"})

          create(:charge_filter, charge:, properties: {amount: "5"}, invoice_display_name: "All clouds")
            .tap { |cf| create(:charge_filter_value, charge_filter: cf, billable_metric_filter: cloud_filter, values: %w[aws gcp]) }
          create(:charge_filter, charge:, properties: {amount: "3"}, invoice_display_name: "AWS only")
            .tap { |cf| create(:charge_filter_value, charge_filter: cf, billable_metric_filter: cloud_filter, values: ["aws"]) }
        end

        it "counts each event only in its most specific bucket" do
          travel_to(DateTime.new(2024, 3, 5)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code
              }
            )
          end

          travel_to(DateTime.new(2024, 3, 6)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: customer.external_id,
                properties: {cloud: "aws", value: 10}
              }
            )

            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: customer.external_id,
                properties: {cloud: "gcp", value: 7}
              }
            )

            fetch_current_usage(customer:)

            filters = json[:customer_usage][:charges_usage].first[:filters]
            expect(filters.count).to eq(3)

            all_clouds = filters.find { |f| f[:invoice_display_name] == "All clouds" }
            expect(all_clouds[:events_count]).to eq(1)
            expect(all_clouds[:units]).to eq("7.0")
            expect(all_clouds[:amount_cents]).to eq(3500)

            aws_only = filters.find { |f| f[:invoice_display_name] == "AWS only" }
            expect(aws_only[:events_count]).to eq(1)
            expect(aws_only[:units]).to eq("10.0")
            expect(aws_only[:amount_cents]).to eq(3000)
          end
        end
      end

      # Duplicate filters with identical values should not exist but can due
      # to missing validations. Each duplicate is kept verbatim in the other's
      # ignored_filters, so they exclude each other and neither counts events.
      context "when two charge filters have identical values" do
        before do
          cloud_filter = create(:billable_metric_filter, billable_metric:, key: "cloud", values: %w[aws gcp])

          charge = create(:standard_charge, plan:, billable_metric:, properties: {amount: "10"})

          create(:charge_filter, charge:, properties: {amount: "5"}, invoice_display_name: "Duplicate A")
            .tap { |cf| create(:charge_filter_value, charge_filter: cf, billable_metric_filter: cloud_filter, values: ["aws"]) }
          create(:charge_filter, charge:, properties: {amount: "3"}, invoice_display_name: "Duplicate B")
            .tap { |cf| create(:charge_filter_value, charge_filter: cf, billable_metric_filter: cloud_filter, values: ["aws"]) }
        end

        it "counts the event in neither duplicate's bucket" do
          travel_to(DateTime.new(2024, 3, 5)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code
              }
            )
          end

          travel_to(DateTime.new(2024, 3, 6)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: customer.external_id,
                properties: {cloud: "aws", value: 10}
              }
            )

            fetch_current_usage(customer:)

            filters = json[:customer_usage][:charges_usage].first[:filters]
            expect(filters.count).to eq(3)

            duplicate_a = filters.find { |f| f[:invoice_display_name] == "Duplicate A" }
            expect(duplicate_a[:events_count]).to eq(0)
            expect(duplicate_a[:units]).to eq("0.0")
            expect(duplicate_a[:amount_cents]).to eq(0)

            duplicate_b = filters.find { |f| f[:invoice_display_name] == "Duplicate B" }
            expect(duplicate_b[:events_count]).to eq(0)
            expect(duplicate_b[:units]).to eq("0.0")
            expect(duplicate_b[:amount_cents]).to eq(0)
          end
        end
      end
    end
  end
end
