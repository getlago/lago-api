# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivateService, clickhouse: true do
  subject(:activate_service) { described_class.new(timestamp: timestamp.to_i) }

  let(:timestamp) { Time.current }

  describe ".activate_all_pending" do
    it "activates all pending subscriptions with subscription date set to today" do
      create(:subscription)
      create_list(:subscription, 2, :pending, subscription_at: timestamp)
      create(:subscription, :pending, subscription_at: timestamp, plan: create(:plan, pay_in_advance: true))
      create_list(:subscription, 2, :pending, subscription_at: (timestamp + 10.days))

      expect { activate_service.activate_all_pending }
        .to change(Subscription.pending, :count).by(-3)
        .and change(Subscription.active, :count).by(3)
        .and have_enqueued_job(SendWebhookJob).exactly(3).times
        .and have_enqueued_job(BillSubscriptionJob).once
      expect(Utils::ActivityLog).to have_received(:produce)
        .with(an_instance_of(Subscription), "subscription.started").exactly(3).times
    end

    context "when plan has fixed charges" do
      let(:plan) { create(:plan) }
      let(:fixed_charge_1) { create(:fixed_charge, plan:) }
      let(:subscription) { create(:subscription, :pending, subscription_at: timestamp, plan:) }

      before do
        fixed_charge_1
        subscription
      end

      it "creates fixed charge events for the new subscription" do
        expect { activate_service.activate_all_pending }.to change(FixedChargeEvent, :count).by(1)
        expect(subscription.fixed_charge_events.pluck(:fixed_charge_id, :timestamp)).to match_array(
          [
            [fixed_charge_1.id, be_within(5.seconds).of(Time.current)]
          ]
        )
      end
    end

    context "with customer timezone" do
      let(:timestamp) { DateTime.parse("2023-08-24 00:07:00") }
      let(:customer) { create(:customer, :with_hubspot_integration, timezone: "America/Bogota") }
      let!(:pending_subscription) do
        create(
          :subscription,
          :pending,
          customer:,
          subscription_at: timestamp
        )
      end

      it "enqueues Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob" do
        allow(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob).to receive(:perform_later)
        activate_service.activate_all_pending
        expect(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob)
          .to have_received(:perform_later).with(subscription: pending_subscription)
      end

      it "takes timezone into account" do
        activate_service.activate_all_pending
        expect(pending_subscription.reload).to be_active
      end
    end

    context "with a subscription in trial" do
      it do
        create(:subscription, :pending, subscription_at: timestamp, plan: create(:plan, pay_in_advance: true))
        create(
          :subscription,
          :pending,
          subscription_at: timestamp,
          plan: create(:plan, pay_in_advance: true, trial_period: 10)
        )

        expect { activate_service.activate_all_pending }
          .to change(Subscription.pending, :count).by(-2)
          .and change(Subscription.active, :count).by(2)
          .and have_enqueued_job(SendWebhookJob).exactly(2).times
          .and have_enqueued_job(BillSubscriptionJob).once
      end
    end
  end
end
