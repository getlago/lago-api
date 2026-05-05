# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::FillHistoryService do
  let(:service) { described_class.new(subscription:, from_date:, to_date:) }

  describe "#call" do
    subject(:call_service) { service.call }

    let(:organization) { create(:organization) }
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:customer) { create(:customer, organization:, billing_entity:) }
    let(:plan) { create(:plan, organization:) }
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:subscription_started_at) { Time.zone.parse("2024-10-01 00:00:00") }
    let(:subscription) do
      create(
        :subscription,
        :calendar,
        customer:,
        plan:,
        started_at: subscription_started_at,
        subscription_at: subscription_started_at
      )
    end
    let(:from_date) { Date.parse("2024-10-15") }
    let(:to_date) { Date.parse("2024-10-15") }

    context "when the only consumed charge is free (zero amount)" do
      before do
        create(:standard_charge, plan:, billable_metric:, properties: {amount: "0"})
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: Time.zone.parse("2024-10-15 10:00:00"),
          created_at: Time.zone.parse("2024-10-15 10:00:00")
        )
      end

      it "creates a daily usage based on consumed units" do
        travel_to(Time.zone.parse("2024-10-16 12:00:00")) do
          expect { call_service }.to change(DailyUsage, :count).by(1)

          daily_usage = DailyUsage.order(created_at: :asc).last
          expect(daily_usage).to have_attributes(
            organization_id: organization.id,
            customer_id: customer.id,
            subscription_id: subscription.id,
            usage_date: Date.parse("2024-10-15")
          )
          expect(daily_usage.usage["amount_cents"]).to eq(0)
          expect(daily_usage.usage["charges_usage"].count).to eq(1)
        end
      end
    end

    context "when there is no usage at all" do
      before { create(:standard_charge, plan:, billable_metric:) }

      it "does not create a daily usage" do
        travel_to(Time.zone.parse("2024-10-16 12:00:00")) do
          expect { call_service }.not_to change(DailyUsage, :count)
        end
      end
    end
  end

  describe "#to" do
    subject(:to) { service.to }

    let(:subscription) { create(:subscription, started_at: Time.current - 1.month) }
    let(:from_date) { Time.zone.today - 2.weeks }
    let(:to_date) { nil }

    context "when subscription is terminated" do
      before { Subscriptions::TerminateService.call(subscription:) }

      let(:to_date) { Time.zone.today + 1.week }

      it "returns the terminated_at date" do
        expect(subject).to eq(subscription.terminated_at.to_date)
      end
    end

    context "when subscription is active" do
      context "when to_date is provided" do
        let(:to_date) { Time.zone.today + 1.week }

        it "returns the to_date date" do
          expect(subject).to eq(to_date)
        end
      end

      context "when to_date is nil" do
        it "returns yesterday" do
          expect(subject).to eq(Time.zone.yesterday)
        end
      end
    end
  end
end
