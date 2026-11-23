# frozen_string_literal: true

require "rails_helper"

describe "Aggregation - Weighted Sum Scenarios", transaction: false do
  [
    :postgres,
    :clickhouse
  ].each do |store|
    context "with #{store} store", clickhouse: store == :clickhouse do
      let(:organization) { create(:organization, webhook_url: nil, clickhouse_events_store: store == :clickhouse) }
      let(:customer) { create(:customer, organization:) }

      let(:plan) { create(:plan, organization:, amount_cents: 0) }
      let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }
      let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}) }

      before { charge }

      it "creates fees and keeps the units between periods" do
        travel_to(DateTime.new(2023, 3, 5)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code
            }
          )
        end

        subscription = customer.subscriptions.first

        travel_to(DateTime.new(2023, 3, 5)) do
          create_event(
            {
              code: billable_metric.code,
              external_subscription_id: subscription.external_id,
              properties: {value: "2500"}
            }
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(217_742)

          # TODO: make sure Clickhouse has the same precision as Postgres

          expected_units = (store == :clickhouse) ? "2177.41935483870967741936" : "2177.4193548387096774"
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq(expected_units)
        end

        travel_to(DateTime.new(2023, 4, 1)) do
          expect { perform_billing }
            .to change { subscription.reload.invoices.count }.from(0).to(1)
            .and change { organization.reload.cached_aggregations.count }.from(0).to(1)
        end

        invoice = subscription.invoices.first
        expect(invoice.fees.charge.count).to eq(1)

        fee = invoice.fees.charge.first
        expect(fee.amount_cents).to eq(217_742)
        expect(fee.units.round).to eq(2177)
        expect(fee.total_aggregated_units).to eq(2500)

        cached_aggregation = CachedAggregation.order(created_at: :desc).first
        expect(cached_aggregation.current_aggregation).to eq(2500.0)

        travel_to(DateTime.new(2023, 4, 4)) do
          create_event(
            {
              code: billable_metric.code,
              external_subscription_id: subscription.external_id,
              properties: {value: "-2000"}
            }
          )
        end

        travel_to(DateTime.new(2023, 4, 6)) do
          create_event(
            {
              code: billable_metric.code,
              external_subscription_id: subscription.external_id,
              properties: {value: "-200"}
            }
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(53_333)

          # TODO: make sure Clickhouse has the same precision as Postgres
          expected_units = (store == :clickhouse) ? "533.33333333333333333334" : "533.3333333333333333"
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq(expected_units)
        end

        travel_to(DateTime.new(2023, 5, 1)) do
          expect { perform_billing }
            .to change { subscription.reload.invoices.count }.from(1).to(2)
            .and change { organization.reload.cached_aggregations.count }.from(1).to(2)
        end

        invoice = subscription.invoices.order(:created_at).last
        expect(invoice.fees.charge.count).to eq(1)

        fee = invoice.fees.charge.first
        expect(fee.amount_cents).to eq(53_333)
        expect(fee.units.round(5)).to eq(533.33333)
        expect(fee.total_aggregated_units).to eq(300)

        cached_aggregation = CachedAggregation.order(:created_at).last
        expect(cached_aggregation.current_aggregation).to eq(300.0)
      end
    end
  end

  context "with clickhouse store and a weighted sum above the Decimal128 limit", clickhouse: true do
    let(:organization) { create(:organization, webhook_url: nil, clickhouse_events_store: true) }
    let(:customer) { create(:customer, organization:) }

    let(:plan) { create(:plan, organization:, amount_cents: 0) }
    let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }
    let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}) }

    before { charge }

    it "bills the exact units without wrapping" do
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

      travel_to(DateTime.new(2023, 3, 1)) do
        create_event(
          {
            code: billable_metric.code,
            external_subscription_id: subscription.external_id,
            properties: {value: "1000000"}
          }
        )
      end

      travel_to(DateTime.new(2023, 3, 15)) do
        fetch_current_usage(customer:)

        # 1,000,000 held the 31 days of March: 1e6 x 2,678,400 s / 2,678,400 s.
        # The product 2.6784e12 wrapped in Decimal128.
        expect(json[:customer_usage][:charges_usage][0][:units]).to eq("1000000.0")
        expect(json[:customer_usage][:total_amount_cents]).to eq(100_000_000) # 1,000,000 units x 1 x 100
      end

      travel_to(DateTime.new(2023, 4, 1)) do
        expect { perform_billing }
          .to change { subscription.reload.invoices.count }.from(0).to(1)
      end

      fee = subscription.invoices.first.fees.charge.sole
      expect(fee.units).to eq(1_000_000)
      expect(fee.amount_cents).to eq(100_000_000) # 1,000,000 units x 1 x 100
      expect(fee.total_aggregated_units).to eq(1_000_000)
    end
  end
end
