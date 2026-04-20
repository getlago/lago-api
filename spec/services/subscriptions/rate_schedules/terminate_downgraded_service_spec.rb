# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::RateSchedules::TerminateDowngradedService do
  subject(:terminate_service) { described_class.new(subscription:, timestamp:) }

  describe "#call" do
    let(:organization) { create(:organization) }
    let(:plan) { create(:plan, organization:) }
    let(:product) { create(:product, organization:) }
    let(:product_item) { create(:product_item, :subscription, product:, organization:) }
    let(:plan_product_item) { create(:plan_product_item, plan:, product_item:, organization:) }

    let(:rate_schedule) { create(:rate_schedule, plan_product_item:, organization:) }
    let(:subscription_rate_schedule) { create(:subscription_rate_schedule, subscription:, product_item:, rate_schedule:, organization:) }

    let(:subscription) { create(:subscription, plan:) }
    let(:next_subscription) { create(:subscription, :pending, plan:, previous_subscription: subscription) }
    let(:timestamp) { Time.zone.now.to_i }

    before do
      subscription_rate_schedule
      next_subscription
    end

    it "terminates the current subscription" do
      result = terminate_service.call

      expect(result).to be_success
      expect(subscription.reload).to be_terminated
    end

    it "bills the current subscription" do
      expect { terminate_service.call }.to have_enqueued_job(Invoices::RateSchedulesBillingJob)
    end

    it "starts the next subscription" do
      result = terminate_service.call

      expect(result).to be_success
      expect(result.subscription.id).to eq(next_subscription.id)
      expect(result.subscription).to be_active
    end

    it "sends subscription.terminated and subscription.started webhooks" do
      terminate_service.call
      expect(SendWebhookJob).to have_been_enqueued.with("subscription.terminated", subscription)
      expect(SendWebhookJob).to have_been_enqueued.with("subscription.started", next_subscription)
    end

    it "logs subscription.terminated and subscription.started events" do
      terminate_service.call
      expect(Utils::ActivityLog).to have_produced("subscription.terminated").with(subscription)
      expect(Utils::ActivityLog).to have_produced("subscription.started").with(next_subscription)
    end

    context "when plan has fixed product items", skip: "until this part is reworked for the rate schedules case" do
      let(:fixed_charge) { create(:fixed_charge, plan: next_subscription.plan) }

      before { fixed_charge }

      it "creates fixed charge events for the new subscription" do
        result = terminate_service.call
        expect(result.subscription.fixed_charge_events.pluck(:fixed_charge_id, :timestamp))
          .to match_array([[fixed_charge.id, be_within(5.seconds).of(Time.zone.at(timestamp))]])
      end
    end

    context "when next subscription is pay in advance" do
      let(:rate_schedule) { create(:rate_schedule, :pay_in_advance, plan_product_item:, organization:) }
      let(:next_subscription) do
        create(
          :subscription,
          :pending,
          plan:,
          previous_subscription: subscription
        )
      end
      let(:next_subscription_rate_schedule) { create(:subscription_rate_schedule, subscription: next_subscription, rate_schedule:) }

      before do
        next_subscription_rate_schedule
      end

      it "bills the next subscription" do
        terminate_service.call

        expect(Invoices::RateSchedulesBillingJob).to have_been_enqueued
          .with([subscription_rate_schedule, next_subscription_rate_schedule], timestamp, invoicing_reason: :upgrading)
      end
    end
  end
end
