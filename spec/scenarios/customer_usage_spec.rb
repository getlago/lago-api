# frozen_string_literal: true

require "rails_helper"

describe "Customer usage Scenario", cache: :redis do
  let(:organization) { create(:organization, webhook_url: nil) }

  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:, currency: "EUR") }

  let(:plan) { create(:plan, organization:, amount_cents: 5000, pay_in_advance: false, interval: "yearly") }
  let(:billable_metric) { create(:billable_metric, organization:, code: "image_generation", name: "Image generation") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, invoice_display_name: "Image generation") }

  before { charge }

  def customer_usage_json(units: 1.0, from_datetime: "2043-01-01T09:30:00Z", to_datetime: "2043-12-31T23:59:59Z")
    total_amount_cents = 1000 * units
    {
      customer_usage: {
        amount_cents: total_amount_cents,
        charges_usage: [
          {
            amount_cents: total_amount_cents,
            amount_currency: "EUR",
            billable_metric: {
              aggregation_type: "count_agg",
              code: "image_generation",
              lago_id: billable_metric.id,
              name: billable_metric.name
            },
            charge: {
              charge_model: "standard",
              invoice_display_name: "Image generation",
              lago_id: charge.id
            },
            events_count: units.to_i,
            filters: [],
            grouped_usage: [],
            pricing_unit_details: nil,
            total_aggregated_units: units.to_d.to_s,
            units: units.to_d.to_s
          }
        ],
        currency: "EUR",
        from_datetime: from_datetime,
        issuing_date: to_datetime.slice(0, 10),
        lago_invoice_id: nil,
        taxes_amount_cents: 0,
        to_datetime: to_datetime,
        total_amount_cents: total_amount_cents
      }
    }
  end

  def fetch_and_assert_current_usage(units: 1.0, from_datetime: "2043-01-01T09:30:00Z", to_datetime: "2043-12-31T23:59:59Z")
    subscription = customer.subscriptions.first
    fetch_current_usage(customer:, subscription:)

    expect(json).to eq(customer_usage_json(units: units, from_datetime: from_datetime, to_datetime: to_datetime))
  end

  context "with start date in the past" do
    it "retrieve the customer usage" do
      travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
        subscription = create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
          },
          as: :model
        )

        fetch_and_assert_current_usage(units: 0)

        create_event({
          external_subscription_id: subscription.external_id,
          timestamp: Time.now.to_f,
          code: "image_generation",
          properties: {}
        })

        fetch_and_assert_current_usage(units: 1)

        # test cache
        fetch_and_assert_current_usage(units: 1)

        create_event({
          external_subscription_id: subscription.external_id,
          timestamp: Time.now.to_f,
          code: "image_generation",
          properties: {}
        })

        fetch_and_assert_current_usage(units: 2)

        Event.last.discard

        # test cache
        fetch_and_assert_current_usage(units: 2)

        Rails.cache.clear

        fetch_and_assert_current_usage(units: 1)
      end
    end

    context "with Europe/Berlin timezone" do
      let(:timezone) { "Europe/Berlin" }

      it "retrieve the customer usage" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            }
          )

          fetch_and_assert_current_usage(units: 0, from_datetime: "2043-01-01T09:30:00Z", to_datetime: "2043-12-31T22:59:59Z")
        end
      end
    end

    context "with America/Los_Angeles timezone" do
      let(:timezone) { "America/Los_Angeles" }

      it "retrieve the customer usage" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            }
          )

          fetch_and_assert_current_usage(units: 0, from_datetime: "2043-01-01T09:30:00Z", to_datetime: "2044-01-01T07:59:59Z")
        end
      end
    end

    context "with multiple charges and cache isolation" do
      let(:billable_metric_b) { create(:billable_metric, organization:, code: "api_calls", name: "API calls") }
      let(:charge_b) { create(:standard_charge, plan:, billable_metric: billable_metric_b, invoice_display_name: "API calls") }

      before { charge_b }

      it "caches each charge independently and invalidates only the affected charge" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          subscription = create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            },
            as: :model
          )

          # Send event for metric A
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {}
          })

          fetch_current_usage(customer:, subscription:)
          charges_usage = json[:customer_usage][:charges_usage]
          expect(charges_usage.size).to eq(2)

          api_usage = charges_usage.find { |c| c[:billable_metric][:code] == "api_calls" }
          img_usage = charges_usage.find { |c| c[:billable_metric][:code] == "image_generation" }
          expect(img_usage[:units]).to eq("1.0")
          expect(api_usage[:units]).to eq("0.0")

          # Second fetch should use cache and return same results
          fetch_current_usage(customer:, subscription:)
          charges_usage = json[:customer_usage][:charges_usage]
          img_usage = charges_usage.find { |c| c[:billable_metric][:code] == "image_generation" }
          api_usage = charges_usage.find { |c| c[:billable_metric][:code] == "api_calls" }
          expect(img_usage[:units]).to eq("1.0")
          expect(api_usage[:units]).to eq("0.0")

          # Send event for metric B only — should invalidate only metric B's cache
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "api_calls",
            properties: {}
          })

          fetch_current_usage(customer:, subscription:)
          charges_usage = json[:customer_usage][:charges_usage]
          img_usage = charges_usage.find { |c| c[:billable_metric][:code] == "image_generation" }
          api_usage = charges_usage.find { |c| c[:billable_metric][:code] == "api_calls" }
          expect(img_usage[:units]).to eq("1.0")
          expect(api_usage[:units]).to eq("1.0")
        end
      end
    end

    context "with grouped_by and cache" do
      let(:charge) do
        create(:standard_charge, plan:, billable_metric:,
          invoice_display_name: "Image generation",
          properties: {amount: "10", grouped_by: %w[region]})
      end

      it "preserves grouped_by nil values through the cache" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          subscription = create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            },
            as: :model
          )

          # Event with region
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {region: "us"}
          })

          # Event without region (nil group key)
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {}
          })

          fetch_current_usage(customer:, subscription:)
          grouped_usage = json[:customer_usage][:charges_usage].first[:grouped_usage]
          expect(grouped_usage.size).to eq(2)

          us_group = grouped_usage.find { |g| g[:grouped_by][:region] == "us" }
          nil_group = grouped_usage.find { |g| g[:grouped_by][:region].nil? }
          expect(us_group[:units]).to eq("1.0")
          expect(nil_group[:units]).to eq("1.0")

          # Second fetch should use cache and return identical grouped results
          fetch_current_usage(customer:, subscription:)
          grouped_usage = json[:customer_usage][:charges_usage].first[:grouped_usage]
          expect(grouped_usage.size).to eq(2)

          us_group = grouped_usage.find { |g| g[:grouped_by][:region] == "us" }
          nil_group = grouped_usage.find { |g| g[:grouped_by][:region].nil? }
          expect(us_group[:units]).to eq("1.0")
          expect(nil_group[:units]).to eq("1.0")

          # New event invalidates cache, updated totals
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {region: "us"}
          })

          fetch_current_usage(customer:, subscription:)
          grouped_usage = json[:customer_usage][:charges_usage].first[:grouped_usage]
          us_group = grouped_usage.find { |g| g[:grouped_by][:region] == "us" }
          nil_group = grouped_usage.find { |g| g[:grouped_by][:region].nil? }
          expect(us_group[:units]).to eq("2.0")
          expect(nil_group[:units]).to eq("1.0")
        end
      end
    end

    context "with charge filters and cache" do
      let(:billable_metric_filter) do
        create(:billable_metric_filter, billable_metric:, key: "cloud", values: %w[aws gcp])
      end
      let(:charge_filter) do
        create(:charge_filter, charge:, properties: {amount: "20"})
      end
      let(:charge_filter_value) do
        create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: %w[aws])
      end

      before { charge_filter_value }

      it "caches filtered usage correctly" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          subscription = create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            },
            as: :model
          )

          # Event matching the aws filter
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {cloud: "aws"}
          })

          # Event not matching any filter (default charge pricing)
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {cloud: "gcp"}
          })

          fetch_current_usage(customer:, subscription:)
          charge_usage = json[:customer_usage][:charges_usage].first
          expect(charge_usage[:units]).to eq("2.0")
          # aws filter: 1 unit * 20 = 2000, default: 1 unit * 10 = 1000
          expect(charge_usage[:amount_cents]).to eq(3000)
          expect(charge_usage[:filters].size).to eq(2)

          aws_filter = charge_usage[:filters].find { |f| f[:values] == {cloud: %w[aws]} }
          default_filter = charge_usage[:filters].find { |f| f[:values].nil? }
          expect(aws_filter[:units]).to eq("1.0")
          expect(aws_filter[:amount_cents]).to eq(2000)
          expect(default_filter[:units]).to eq("1.0")
          expect(default_filter[:amount_cents]).to eq(1000)

          # Second fetch should use cache
          fetch_current_usage(customer:, subscription:)
          charge_usage = json[:customer_usage][:charges_usage].first
          expect(charge_usage[:amount_cents]).to eq(3000)
          expect(charge_usage[:filters].size).to eq(2)

          # New event invalidates cache
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {cloud: "aws"}
          })

          fetch_current_usage(customer:, subscription:)
          charge_usage = json[:customer_usage][:charges_usage].first
          expect(charge_usage[:units]).to eq("3.0")
          # aws filter: 2 units * 20 = 4000, default: 1 unit * 10 = 1000
          expect(charge_usage[:amount_cents]).to eq(5000)
        end
      end
    end

    context "with charge update invalidating cache" do
      it "reflects updated charge properties after cache key changes" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          subscription = create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            },
            as: :model
          )

          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {}
          })

          # Initial usage: 1 unit * 10 = 1000 cents
          fetch_and_assert_current_usage(units: 1)

          # Cache should serve same result
          fetch_and_assert_current_usage(units: 1)

          # Update charge amount from 10 to 20 (this changes charge.updated_at, invalidating cache key)
          update_plan(plan, {
            charges: [{
              id: charge.id,
              billable_metric_id: billable_metric.id,
              charge_model: "standard",
              invoice_display_name: "Image generation",
              properties: {amount: "20"}
            }]
          })

          # Usage should reflect new price: 1 unit * 20 = 2000 cents
          fetch_current_usage(customer:, subscription:)
          expect(json[:customer_usage][:charges_usage].first[:amount_cents]).to eq(2000)
          expect(json[:customer_usage][:charges_usage].first[:units]).to eq("1.0")
        end
      end
    end
  end
end
