# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::ActivateService, type: :service do
  subject(:activate_service) { described_class.new(timestamp: timestamp.to_i) }

  let(:timestamp) { Time.current }

  describe '.activate_all_pending' do
    it 'activates all pending subscriptions with subscription date set to today' do
      create(:subscription)
      create_list(:subscription, 2, :pending, subscription_at: timestamp)
      create(:subscription, :pending, subscription_at: timestamp, plan: create(:plan, pay_in_advance: true))
      create_list(:subscription, 2, :pending, subscription_at: (timestamp + 10.days))

      expect { activate_service.activate_all_pending }
        .to change(Subscription.pending, :count).by(-3)
        .and change(Subscription.active, :count).by(3)
        .and have_enqueued_job(SendWebhookJob).exactly(3).times
        .and have_enqueued_job(BillSubscriptionJob).once
    end

    context 'with customer timezone' do
      let(:timestamp) { DateTime.parse('2023-08-24 00:07:00') }
      let(:customer) { create(:customer, :with_hubspot_integration, timezone: 'America/Bogota') }
      let!(:pending_subscription) do
        create(
          :subscription,
          :pending,
          customer:,
          subscription_at: timestamp
        )
      end

      it 'enqueues Integrations::Aggregator::Subscriptions::Crm::UpdateJob' do
        allow(Integrations::Aggregator::Subscriptions::Crm::UpdateJob).to receive(:perform_later)
        activate_service.activate_all_pending
        expect(Integrations::Aggregator::Subscriptions::Crm::UpdateJob)
          .to have_received(:perform_later).with(subscription: pending_subscription)
      end

      it 'takes timezone into account' do
        activate_service.activate_all_pending
        expect(pending_subscription.reload).to be_active
      end
    end

    context 'with a subscription in trial' do
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
