# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::ComputeAllService do
  subject(:compute_service) { described_class.new(timestamp:) }

  let(:timestamp) { Time.zone.parse("2024-10-22 00:05:00") }

  let(:organization) { create(:organization, premium_integrations:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscriptions) { create_list(:subscription, 5, customer:, renew_daily_usage: true) }

  let(:premium_integrations) do
    ["revenue_analytics"]
  end

  before { subscriptions }

  describe "#call" do
    it "enqueues a job to compute the daily usage" do
      expect(compute_service.call).to be_success
      subscriptions.each do |subscription|
        expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:).at(0.minutes.from_now..30.minutes.from_now)
      end
    end

    context "when LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS is set" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS" => "60")) }

      it "uses the configured interval" do
        expect(compute_service.call).to be_success
        subscriptions.each do |subscription|
          expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:).at(0.seconds.from_now..60.seconds.from_now)
        end
      end
    end

    context "when LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS is negative" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS" => "-100")) }

      it "falls back to the default interval" do
        expect(compute_service.call).to be_success
        subscriptions.each do |subscription|
          expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:).at(0.minutes.from_now..30.minutes.from_now)
        end
      end
    end

    context "when LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS is zero" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS" => "0")) }

      it "falls back to the default interval" do
        expect(compute_service.call).to be_success
        subscriptions.each do |subscription|
          expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:).at(0.minutes.from_now..30.minutes.from_now)
        end
      end
    end

    context "when LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS is non-numeric" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS" => "invalid")) }

      it "falls back to the default interval" do
        expect(compute_service.call).to be_success
        subscriptions.each do |subscription|
          expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:).at(0.minutes.from_now..30.minutes.from_now)
        end
      end
    end

    context "when LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS is blank" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS" => "")) }

      it "falls back to the default interval" do
        expect(compute_service.call).to be_success
        subscriptions.each do |subscription|
          expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:).at(0.minutes.from_now..30.minutes.from_now)
        end
      end
    end

    context "when subscription usage was already computed" do
      before { create(:daily_usage, subscription: subscriptions.first, usage_date: timestamp.to_date - 1.day) }

      it "does not enqueue any job" do
        expect(compute_service.call).to be_success
        expect(DailyUsages::ComputeJob).not_to have_been_enqueued.with(subscriptions.first, timestamp:)
        subscriptions[1..].each do |subscription|
          expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:).at(0.minutes.from_now..30.minutes.from_now)
        end
      end
    end

    context "when the organization has a timezone" do
      let(:organization) { create(:organization, timezone: "America/Sao_Paulo", premium_integrations:) }

      before do
        organization.default_billing_entity.update(timezone: "America/Sao_Paulo")
      end

      it "takes the timezone into account" do
        expect(compute_service.call).to be_success
        expect(DailyUsages::ComputeJob).not_to have_been_enqueued
      end

      context "when the day starts in the timezone" do
        let(:timestamp) { Time.zone.parse("2024-10-22 03:05:00") }

        it "enqueues a job to compute the daily usage" do
          expect(compute_service.call).to be_success
          subscriptions.each do |subscription|
            expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:)
          end
        end
      end
    end

    context "when the customer has a timezone" do
      let(:customer) { create(:customer, organization:, timezone: "America/Sao_Paulo") }

      it "takes the timezone into account" do
        expect(compute_service.call).to be_success
        expect(DailyUsages::ComputeJob).not_to have_been_enqueued
      end

      context "when the day starts in the timezone" do
        let(:timestamp) { Time.zone.parse("2024-10-22 03:05:00") }

        it "enqueues a job to compute the daily usage" do
          expect(compute_service.call).to be_success
          subscriptions.each do |subscription|
            expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:)
          end
        end
      end
    end

    context "when renew_daily_usage is false" do
      let(:subscriptions) { create_list(:subscription, 5, customer:, renew_daily_usage: false) }

      it "does not enqueue any job" do
        expect(compute_service.call).to be_success
        expect(DailyUsages::ComputeJob).not_to have_been_enqueued
      end
    end

    context "when revenue_analytics premium integration flag is not present" do
      let(:premium_integrations) { [] }

      it "does not enqueue any job" do
        expect(compute_service.call).to be_success
        expect(DailyUsages::ComputeJob).not_to have_been_enqueued
      end
    end
  end
end
