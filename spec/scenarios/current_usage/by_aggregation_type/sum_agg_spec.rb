# frozen_string_literal: true

require "rails_helper"

describe "Aggregation - Sum Scenarios", transaction: false do
  [
    :postgres,
    :clickhouse
  ].each do |store|
    context "with #{store} store", clickhouse: store == :clickhouse do
      let(:organization) { create(:organization, webhook_url: nil, clickhouse_events_store: store == :clickhouse) }
      let(:customer) { create(:customer, organization:) }

      let(:plan) { create(:plan, organization:, amount_cents: 0) }
      let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }

      before { charge }

      context "with in advance charge and groups" do
        let(:charge) do
          create(
            :standard_charge,
            billable_metric:,
            plan:,
            prorated: true,
            pay_in_advance: true,
            properties: {
              amount: "29",
              grouped_by: %w[key_1 key_2 key_3]
            }
          )
        end

        it "creates fees for each events" do
          travel_to(DateTime.new(2024, 2, 1)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code
              }
            )
          end

          subscription = customer.subscriptions.first

          travel_to(DateTime.new(2024, 2, 6, 1)) do
            create_event(
              {
                code: billable_metric.code,
                external_subscription_id: subscription.external_id,
                properties: {
                  "item_id" => 10,
                  "key_1" => "2024",
                  "key_2" => "Feb",
                  "key_3" => "06"
                }
              }
            )

            expect(Fee.count).to eq(1)

            fetch_current_usage(customer:)
            expect(json[:customer_usage][:total_amount_cents]).to eq(24_000)
            expect(json[:customer_usage][:charges_usage].first[:units]).to eq("10.0")
          end

          travel_to(DateTime.new(2024, 2, 6, 2)) do
            create_event(
              {
                code: billable_metric.code,
                external_subscription_id: subscription.external_id,
                properties: {
                  "item_id" => -5,
                  "key_1" => "2024",
                  "key_2" => "Feb",
                  "key_3" => "06"
                }
              }
            )

            expect(Fee.count).to eq(2)

            fetch_current_usage(customer:)
            expect(json[:customer_usage][:total_amount_cents]).to eq(24_000)
            expect(json[:customer_usage][:charges_usage].first[:units]).to eq("5.0")
          end

          travel_to(DateTime.new(2024, 2, 6, 3)) do
            create_event(
              {
                code: billable_metric.code,
                external_subscription_id: subscription.external_id,
                properties: {
                  "item_id" => 2,
                  "key_1" => "2024",
                  "key_2" => "Feb",
                  "key_3" => "06"
                }
              }
            )

            expect(Fee.count).to eq(3)

            fetch_current_usage(customer:)
            expect(json[:customer_usage][:total_amount_cents]).to eq(24_000)
            expect(json[:customer_usage][:charges_usage].first[:units]).to eq("7.0")
          end
        end
      end

      context "with in advance prorated charge and a rounded fractional sum" do
        let(:plan) { create(:plan, organization:, amount_cents: 0, interval: :monthly) }
        let(:billable_metric) do
          create(:sum_billable_metric, :recurring, organization:, rounding_function: :ceil, rounding_precision: 0)
        end
        let(:charge) do
          create(
            :standard_charge,
            billable_metric:,
            plan:,
            prorated: true,
            pay_in_advance: true,
            properties: {amount: "0.5"}
          )
        end

        # The subscription starts on Nov 5, so the Nov 5-30 period is billed at 26/30 of a month.
        # Each increase of the running maximum is prorated over the days left in November (out of 30).
        it "bills current usage on the ceiled prorated maximum without a rounding delta" do
          travel_to(DateTime.new(2026, 11, 5)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code
              }
            )
          end

          subscription = customer.subscriptions.first
          snapshots = [
            [DateTime.new(2026, 11, 11, 10), "7.571188657"],
            [DateTime.new(2026, 11, 13, 10), "9.552135703"],
            [DateTime.new(2026, 11, 14, 10), "-3.639498807"],
            [DateTime.new(2026, 11, 15, 10), "18.631375395"]
          ].map do |time, value|
            travel_to(time) do
              create_event(
                {
                  code: billable_metric.code,
                  external_subscription_id: subscription.external_id,
                  properties: {billable_metric.field_name => value}
                }
              )

              fetch_current_usage(customer:)
              charge_usage = json[:customer_usage][:charges_usage].sole
              [charge_usage[:units], charge_usage[:amount_cents]]
            end
          end

          expect(Fee.count).to eq(4)
          # Units are the ceiled running total; the amount is ceil(cached prorated maximum) x 50 cents:
          # Nov 11: 7.571188657 x 20/30 = 5.04746 -> 6 units -> 300
          # Nov 13: 5.04746 + 9.552135703 x 18/30 (5.73129) = 10.77875 -> 11 -> 550
          # Nov 14: the decrease keeps the maximum, 10.77875 -> 11 -> 550
          # Nov 15: 10.77875 + (32.115200951 - 17.12332436) x 16/30 (7.99567) = 18.77442 -> 19 -> 950
          # Counting the rounding as usage would add (ceil(total) - total) x 26/30, giving 600, 600 and 1000.
          expect(snapshots).to eq([["8.0", 300], ["18.0", 550], ["14.0", 550], ["33.0", 950]])
        end
      end

      context "with multiple subscriptions attached to the same plan" do
        let(:charge) do
          create(
            :standard_charge,
            billable_metric:,
            plan:,
            prorated: true,
            pay_in_advance: true,
            properties: {
              amount: "29",
              grouped_by: %w[key_1 key_2 key_3]
            }
          )
        end

        it "creates fees for each events" do
          travel_to(DateTime.new(2024, 2, 1)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: "#{customer.external_id}_1",
                plan_code: plan.code
              }
            )
          end

          subscription1 = customer.subscriptions.first

          travel_to(DateTime.new(2024, 2, 1, 1)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: "#{customer.external_id}_2",
                plan_code: plan.code
              }
            )
          end

          subscription2 = customer.subscriptions.order(:created_at).last

          travel_to(DateTime.new(2024, 2, 6, 0, 1)) do
            create_event(
              {
                code: billable_metric.code,
                external_subscription_id: subscription1.external_id,
                properties: {
                  "item_id" => 10,
                  "key_1" => "2024",
                  "key_2" => "Feb",
                  "key_3" => "06"
                }
              }
            )

            expect(Fee.count).to eq(1)

            fetch_current_usage(customer:, subscription: subscription1)
            expect(json[:customer_usage][:total_amount_cents]).to eq(24_000)
            expect(json[:customer_usage][:charges_usage].first[:units]).to eq("10.0")
          end

          travel_to(DateTime.new(2024, 2, 6, 0, 2)) do
            create_event(
              {
                code: billable_metric.code,
                external_subscription_id: subscription1.external_id,
                properties: {
                  "item_id" => -5,
                  "key_1" => "2024",
                  "key_2" => "Feb",
                  "key_3" => "06"
                }
              }
            )

            expect(Fee.count).to eq(2)

            fetch_current_usage(customer:, subscription: subscription1)
            expect(json[:customer_usage][:total_amount_cents]).to eq(24_000)
            expect(json[:customer_usage][:charges_usage].first[:units]).to eq("5.0")
          end

          travel_to(DateTime.new(2024, 2, 6, 0, 3)) do
            create_event(
              {
                code: billable_metric.code,
                external_subscription_id: subscription1.external_id,
                properties: {
                  "item_id" => 2,
                  "key_1" => "2024",
                  "key_2" => "Feb",
                  "key_3" => "06"
                }
              }
            )

            expect(Fee.count).to eq(3)

            fetch_current_usage(customer:, subscription: subscription1)
            expect(json[:customer_usage][:total_amount_cents]).to eq(24_000)
            expect(json[:customer_usage][:charges_usage].first[:units]).to eq("7.0")
          end

          travel_to(DateTime.new(2024, 2, 6, 1, 0, 1)) do
            create_event(
              {
                code: billable_metric.code,
                external_subscription_id: subscription2.external_id,
                properties: {
                  "item_id" => 10,
                  "key_1" => "2024",
                  "key_2" => "Feb",
                  "key_3" => "06"
                }
              }
            )

            fetch_current_usage(customer:, subscription: subscription2)
            expect(json[:customer_usage][:total_amount_cents]).to eq(24_000)
            expect(json[:customer_usage][:charges_usage].first[:units]).to eq("10.0")
          end

          travel_to(DateTime.new(2024, 2, 6, 1, 0, 2)) do
            create_event(
              {
                code: billable_metric.code,
                external_subscription_id: subscription2.external_id,
                properties: {
                  "item_id" => -5,
                  "key_1" => "2024",
                  "key_2" => "Feb",
                  "key_3" => "06"
                }
              }
            )

            fetch_current_usage(customer:, subscription: subscription2)
            expect(json[:customer_usage][:total_amount_cents]).to eq(24_000)
            expect(json[:customer_usage][:charges_usage].first[:units]).to eq("5.0")
          end

          travel_to(DateTime.new(2024, 2, 6, 1, 0, 3)) do
            create_event(
              {
                code: billable_metric.code,
                external_subscription_id: subscription2.external_id,
                properties: {
                  "item_id" => 2,
                  "key_1" => "2024",
                  "key_2" => "Feb",
                  "key_3" => "06"
                }
              }
            )

            fetch_current_usage(customer:, subscription: subscription2)
            expect(json[:customer_usage][:total_amount_cents]).to eq(24_000)
            expect(json[:customer_usage][:charges_usage].first[:units]).to eq("7.0")
          end
        end
      end

      context "with a total above the ClickHouse Decimal128 limit" do
        let(:billable_metric) { create(:sum_billable_metric, organization:) }
        let(:charge) { create(:standard_charge, billable_metric:, plan:, properties: {amount: "0.000001"}) }

        it "bills the exact units in current usage and on the invoice" do
          travel_to(DateTime.new(2024, 2, 1)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code
              }
            )
          end

          subscription = customer.subscriptions.first

          travel_to(DateTime.new(2024, 2, 6)) do
            # create_event sets a new transaction_id per call, so the 250 events stay distinct.
            250.times do
              create_event(
                {
                  code: billable_metric.code,
                  external_subscription_id: subscription.external_id,
                  properties: {billable_metric.field_name => 8_000_000_000}
                }
              )
            end

            fetch_current_usage(customer:)

            # 250 events x 8e9 = 2e12, above the Decimal128(38, 26) limit of ~1.70e12
            charge_usage = json[:customer_usage][:charges_usage].sole
            expect(charge_usage[:units]).to eq("2000000000000.0")
            expect(charge_usage[:amount_cents]).to eq(200_000_000) # 2e12 units x 0.000001 x 100
            expect(json[:customer_usage][:total_amount_cents]).to eq(200_000_000)
          end

          travel_to(DateTime.new(2024, 3, 1)) do
            expect { perform_billing }
              .to change { subscription.reload.invoices.count }.from(0).to(1)
          end

          invoice = subscription.invoices.sole
          fee = invoice.fees.charge.sole
          expect(fee.units).to eq(2_000_000_000_000) # 250 events x 8e9
          expect(fee.amount_cents).to eq(200_000_000) # 2e12 units x 0.000001 x 100
          expect(invoice.fees_amount_cents).to eq(200_000_000) # charge fee only, the plan costs 0
        end
      end
    end
  end
end
