# frozen_string_literal: true

require "rails_helper"

describe "Charge Models - Dynamic Pricing Scenarios", transaction: false do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:plan) { create(:plan, organization:, amount_cents: 1000) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) do
    create(
      :dynamic_charge,
      plan:,
      billable_metric:,
      properties: charge_properties
    )
  end

  let(:charge_properties) { {} }

  before do
    organization
    customer
    billable_metric
    plan
    charge
  end

  it "returns the expected customer usage" do
    travel_to(DateTime.new(2023, 3, 5)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )
    end

    travel_to(DateTime.new(2023, 3, 6)) do
      create_event(
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: customer.external_id,
          precise_total_amount_cents: "10.1",
          properties: {item_id: "10"}
        }
      )

      fetch_current_usage(customer:)
      expect(json[:customer_usage][:total_amount_cents]).to eq(10)
      expect(json[:customer_usage][:charges_usage][0][:units]).to eq("10.0")

      create_event(
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: customer.external_id,
          precise_total_amount_cents: "901.9",
          properties: {item_id: "10"}
        }
      )

      fetch_current_usage(customer:)
      expect(json[:customer_usage][:total_amount_cents]).to eq(912)
      expect(json[:customer_usage][:charges_usage][0][:units]).to eq("20.0")
    end
  end

  context "with grouping" do
    let(:charge_properties) { {grouped_by: [:group_key]} }

    it "returns the expected customer usage" do
      travel_to(DateTime.new(2023, 3, 5)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
      end

      travel_to(DateTime.new(2023, 3, 6)) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: customer.external_id,
            precise_total_amount_cents: "10.1",
            properties: {item_id: "10", group_key: "value 1"}
          }
        )

        fetch_current_usage(customer:)

        expect(json[:customer_usage][:total_amount_cents]).to eq(10)
        expect(json[:customer_usage][:charges_usage][0][:units]).to eq("10.0")
        expect(json[:customer_usage][:charges_usage][0][:grouped_usage][0][:grouped_by]).to eq({group_key: "value 1"})

        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: customer.external_id,
            precise_total_amount_cents: "901.9",
            properties: {item_id: "10", group_key: "value 2"}
          }
        )

        fetch_current_usage(customer:)
        expect(json[:customer_usage][:total_amount_cents]).to eq(912)
        expect(json[:customer_usage][:charges_usage][0][:units]).to eq("20.0")
        expect(json[:customer_usage][:charges_usage][0][:grouped_usage].size).to eq(2)

        expect(json[:customer_usage][:charges_usage][0][:grouped_usage]).to match_array(
          [
            {amount_cents: 902, events_count: 1, total_aggregated_units: "10.0", units: "10.0", grouped_by: {group_key: "value 2"}, filters: [], pricing_unit_details: nil, presentation_breakdowns: []},
            {amount_cents: 10, events_count: 1, total_aggregated_units: "10.0", units: "10.0", grouped_by: {group_key: "value 1"}, filters: [], pricing_unit_details: nil, presentation_breakdowns: []}
          ]
        )
      end
    end
  end

  context "with ClickHouse", :premium, clickhouse: true do
    let(:organization) do
      create(
        :organization,
        webhook_url: nil,
        email_settings: [],
        premium_integrations: ["preview"],
        clickhouse_events_store: true
      )
    end
    let(:plan) { create(:plan, organization:, amount_cents: 0) }

    {
      "without pricing groups" => {},
      "with pricing groups" => {pricing_group_keys: ["database_name"]}
    }.each do |grouping_context, properties|
      context grouping_context do
        let(:charge_properties) { properties }

        {
          "4312" => 4312,
          "4312.5" => 4313
        }.each do |precise_total_amount_cents, expected_amount_cents|
          it "preserves #{precise_total_amount_cents} precise cents in usage, preview, and billing" do
            travel_to(DateTime.new(2023, 3, 1)) do
              create_subscription(
                {
                  external_customer_id: customer.external_id,
                  external_id: customer.external_id,
                  plan_code: plan.code
                }
              )
            end

            subscription = customer.subscriptions.first

            travel_to(DateTime.new(2023, 3, 6)) do
              create_event(
                {
                  code: billable_metric.code,
                  transaction_id: SecureRandom.uuid,
                  external_subscription_id: subscription.external_id,
                  precise_total_amount_cents:,
                  properties: {item_id: "4", database_name: "qa-db"}
                }
              )

              fetch_current_usage(customer:)
              expect(json[:customer_usage][:total_amount_cents]).to eq(expected_amount_cents)

              if properties.present?
                expect(json[:customer_usage][:charges_usage][0][:grouped_usage][0][:amount_cents]).to eq(expected_amount_cents)
              end

              post_with_token(
                organization,
                "/api/v1/invoices/preview",
                {
                  customer: {external_id: customer.external_id},
                  subscriptions: {external_ids: [subscription.external_id]}
                }
              )

              expect(response).to have_http_status(:success)
              expect(json[:invoice][:fees_amount_cents]).to eq(expected_amount_cents)
            end

            travel_to(DateTime.new(2023, 4, 1)) do
              perform_billing

              expect(subscription.invoices.first.total_amount_cents).to eq(expected_amount_cents)
            end
          end
        end
      end
    end
  end
end
