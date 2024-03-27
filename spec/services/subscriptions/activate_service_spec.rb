# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivateService, type: :service do
  subject(:activate_service) { described_class.new(timestamp: timestamp.to_i) }

  let(:timestamp) { Time.current }

  describe "activate_all_expired" do
    let(:active_subscription) { create(:subscription) }
    let(:pending_subscriptions) { create_list(:pending_subscription, 3, subscription_at: timestamp) }

    let(:future_pending_subscriptions) do
      create_list(:pending_subscription, 2, subscription_at: (timestamp + 10.days))
    end

    before do
      active_subscription
      pending_subscriptions
      future_pending_subscriptions
    end

    it "activates all pending subscriptions with subscription date set to today" do
      expect { activate_service.activate_all_pending }
        .to change(Subscription.pending, :count).by(-3)
        .and change(Subscription.active, :count).by(3)
    end

    it "enqueues a SendWebhookJob" do
      expect do
        activate_service.activate_all_pending
      end.to have_enqueued_job(SendWebhookJob).at_least(1).times
    end

    context "with customer timezone" do
      let(:timestamp) { DateTime.parse("2023-08-24 00:07:00") }
      let(:pending_subscription) { pending_subscriptions.first }

      before do
        pending_subscription.customer.update!(timezone: "America/Bogota")
        pending_subscription.update!(subscription_at: DateTime.parse("2023-08-24 04:17:00"))
      end

      it "takes timezone into account" do
        expect { activate_service.activate_all_pending }
          .to change(Subscription.pending, :count).by(-3)
          .and change(Subscription.active, :count).by(3)
      end
    end
  end
end
