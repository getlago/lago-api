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

        Event.last.destroy

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
  end
end
