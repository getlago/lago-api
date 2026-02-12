# frozen_string_literal: true

require "rails_helper"

describe "Customer usage Scenario" do
  let(:organization) { create(:organization, webhook_url: nil) }

  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:, currency: "EUR") }

  let(:plan) { create(:plan, organization:, amount_cents: 700, pay_in_advance: false, interval: "yearly") }

  context "with start date in the past" do
    it "retrieve the customer usage" do
      travel_to(DateTime.new(2023, 8, 8, 9, 30)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            subscription_at: DateTime.new(2023, 1, 1, 9, 30).iso8601
          }
        )

        subscription = customer.subscriptions.first
        fetch_current_usage(customer:, subscription:)

        expect(json[:customer_usage][:from_datetime]).to eq("2023-01-01T09:30:00Z")
        expect(json[:customer_usage][:to_datetime]).to eq("2023-12-31T23:59:59Z")
      end
    end

    context "with Europe/Berlin timezone" do
      let(:timezone) { "Europe/Berlin" }

      it "retrieve the customer usage" do
        travel_to(DateTime.new(2023, 8, 8, 9, 30)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2023, 1, 1, 9, 30).iso8601
            }
          )

          subscription = customer.subscriptions.first
          fetch_current_usage(customer:, subscription:)

          expect(json[:customer_usage][:from_datetime]).to eq("2023-01-01T09:30:00Z")
          expect(json[:customer_usage][:to_datetime]).to eq("2023-12-31T22:59:59Z")
        end
      end
    end

    context "with America/Los_Angeles timezone" do
      let(:timezone) { "America/Los_Angeles" }

      it "retrieve the customer usage" do
        travel_to(DateTime.new(2023, 8, 8, 9, 30)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2023, 1, 1, 9, 30).iso8601
            }
          )

          subscription = customer.subscriptions.first
          fetch_current_usage(customer:, subscription:)

          expect(json[:customer_usage][:from_datetime]).to eq("2023-01-01T09:30:00Z")
          expect(json[:customer_usage][:to_datetime]).to eq("2024-01-01T07:59:59Z")
        end
      end
    end
  end

  context "with for_charge and for_pricing_group_pairs filtering" do
    let(:plan) { create(:plan, organization:, amount_cents: 0, pay_in_advance: false, interval: "monthly") }

    let(:billable_metric_1) { create(:sum_billable_metric, organization:, field_name: "units") }
    let(:billable_metric_2) { create(:sum_billable_metric, organization:, field_name: "units") }

    let(:charge_1) do
      create(
        :standard_charge,
        plan:,
        billable_metric: billable_metric_1,
        properties: {amount: "10", pricing_group_keys: ["user"]}
      )
    end

    let(:charge_2) do
      create(
        :standard_charge,
        plan:,
        billable_metric: billable_metric_2,
        properties: {amount: "5", pricing_group_keys: ["user"]}
      )
    end

    before do
      charge_1
      charge_2
    end

    let!(:subscription) do
      sub = nil
      travel_to(DateTime.new(2024, 3, 1, 10, 0)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: "anniversary"
          }
        )
        sub = customer.subscriptions.first
      end
      sub
    end

    before do
      travel_to(DateTime.new(2024, 3, 5, 10, 0)) do
        # Send 10 events for charge_1's metric with user 0..9
        10.times do |i|
          create_event(
            {
              code: billable_metric_1.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              properties: {user: i.to_s, units: 5}
            }
          )
        end

        # Send 10 events for charge_2's metric with user 0..9
        10.times do |i|
          create_event(
            {
              code: billable_metric_2.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              properties: {user: i.to_s, units: 3}
            }
          )
        end
      end
    end

    it "with only for_pricing_group_pairs returns one fee per charge filtered to that pair" do
      travel_to(DateTime.new(2024, 3, 10, 10, 0)) do
        result = Invoices::CustomerUsageService.call(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          for_pricing_group_pairs: {user: ["0"]}
        )

        expect(result).to be_success

        fees = result.usage.fees
        expect(fees.size).to eq(2)

        fee_1 = fees.find { |f| f.charge_id == charge_1.id }
        expect(fee_1.units).to eq(5)
        expect(fee_1.events_count).to eq(1)
        expect(fee_1.amount_cents).to eq(5_000) # 5 units * 10 amount * 100 cents

        fee_2 = fees.find { |f| f.charge_id == charge_2.id }
        expect(fee_2.units).to eq(3)
        expect(fee_2.events_count).to eq(1)
        expect(fee_2.amount_cents).to eq(1_500) # 3 units * 5 amount * 100 cents
      end
    end

    it "with only for_charge returns all grouped usage for that charge" do
      travel_to(DateTime.new(2024, 3, 10, 10, 0)) do
        result = Invoices::CustomerUsageService.call(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          for_charge: charge_1
        )

        expect(result).to be_success

        fees = result.usage.fees
        # 10 groups (user 0..9), all for charge_1
        expect(fees.size).to eq(10)
        expect(fees.map(&:charge_id).uniq).to eq([charge_1.id])

        fees.each do |fee|
          expect(fee.units).to eq(5)
          expect(fee.events_count).to eq(1)
          expect(fee.amount_cents).to eq(5_000)
        end

        expect(fees.map { |f| f.grouped_by["user"] }).to match_array(
          (0..9).map(&:to_s)
        )
      end
    end
  end
end
