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
end
