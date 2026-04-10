# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::RateSchedules::TerminateDowngradedService do
  subject(:terminate_service) { described_class.new(subscription:, timestamp:) }

  describe "#call" do
    let(:subscription) { create(:subscription) }
    let(:next_subscription) { create(:subscription, :pending, previous_subscription_id: subscription.id) }
    let(:timestamp) { Time.zone.now.to_i }

    before do
      next_subscription
    end

    it "terminates the subscription" do
      result = terminate_service.call

      expect(result).to be_success
      expect(subscription.reload).to be_terminated
    end

    it "starts the next subscription" do
      result = terminate_service.call

      expect(result).to be_success
      expect(result.subscription.id).to eq(next_subscription.id)
      expect(result.subscription).to be_active
    end

    it "enqueues a SendWebhookJob" do
      terminate_service.call
      expect(SendWebhookJob).to have_been_enqueued.with("subscription.terminated", subscription)
      expect(SendWebhookJob).to have_been_enqueued.with("subscription.started", next_subscription)
    end

    it "produces the activity logs" do
      terminate_service.call
      expect(Utils::ActivityLog).to have_produced("subscription.terminated").with(subscription)
      expect(Utils::ActivityLog).to have_produced("subscription.started").with(next_subscription)
    end

    context "when plan has fixed charges" do
      let(:fixed_charge) { create(:fixed_charge, plan: next_subscription.plan) }

      before { fixed_charge }

      it "creates fixed charge events for the new subscription" do
        result = terminate_service.call
        expect(result.subscription.fixed_charge_events.pluck(:fixed_charge_id, :timestamp))
          .to match_array([[fixed_charge.id, be_within(5.seconds).of(Time.zone.at(timestamp))]])
      end
    end

    context "when terminated subscription is payed in arrear" do
      before { subscription.plan.update!(pay_in_advance: false) }

      it "enqueues a job to bill the existing subscription" do
        expect do
          terminate_service.call
        end.to have_enqueued_job(Invoices::RateSchedulesBillingJob)
      end
    end

    context "when next subscription is payed in advance" do
      let(:plan) { create(:plan, :pay_in_advance) }
      let(:subscription) { create(:subscription, plan:) }
      let(:next_subscription_plan) { create(:plan, :pay_in_advance) }
      let(:next_subscription) do
        create(
          :subscription,
          previous_subscription_id: subscription.id,
          plan: next_subscription_plan,
          status: :pending
        )
      end

      it "enqueues one job" do
        terminate_service.call

        expect(Invoices::RateSchedulesBillingJob).to have_been_enqueued
          .with([subscription, next_subscription], timestamp, invoicing_reason: :upgrading)
      end
    end
  end
end
