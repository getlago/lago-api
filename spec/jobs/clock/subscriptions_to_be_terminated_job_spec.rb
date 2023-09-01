# frozen_string_literal: true

require 'rails_helper'

describe Clock::SubscriptionsToBeTerminatedJob, job: true do
  subject { described_class }

  describe '.perform' do
    let(:ending_at) { (Time.current + 2.months + 15.days).beginning_of_day }
    let(:subscription1) { create(:active_subscription, ending_at:) }
    let(:subscription2) { create(:active_subscription, ending_at: ending_at + 1.year) }
    let(:subscription3) { create(:active_subscription, ending_at: nil) }
    let(:webhook_started1) do
      create(:webhook, :succeeded, object_id: subscription1.id, webhook_type: 'subscription.started')
    end
    let(:webhook_started2) do
      create(:webhook, :succeeded, object_id: subscription2.id, webhook_type: 'subscription.started')
    end
    let(:webhook_started3) do
      create(:webhook, :succeeded, object_id: subscription3.id, webhook_type: 'subscription.started')
    end

    before do
      subscription1
      subscription2
      subscription3
      webhook_started1
      webhook_started2
      webhook_started3
    end

    it 'sends webhook that subscription is going to be terminated for the right subscriptions' do
      current_date = Time.current + 2.months

      travel_to(current_date) do
        expect do
          described_class.perform_now
        end
          .to have_enqueued_job(SendWebhookJob)
          .with('subscription.reaching_termination', Subscription)
          .exactly(:once)
      end
    end

    context 'when the same alert webhook had been already triggered' do
      let(:webhook_alert1) do
        create(:webhook, :succeeded, object_id: subscription1.id, webhook_type: 'subscription.reaching_termination')
      end

      before { webhook_alert1 }

      it 'does not send any webhook' do
        current_date = Time.current + 2.months

        travel_to(current_date) do
          expect do
            described_class.perform_now
          end
            .to have_enqueued_job(SendWebhookJob)
            .with('subscription.reaching_termination', Subscription)
            .exactly(0).times
        end
      end
    end

    context 'with customer timezone' do
      let(:ending_at) { DateTime.parse('2022-10-21 00:30:00') }

      before do
        subscription1.customer.update!(timezone: 'America/New_York')
      end

      it 'takes timezone into account' do
        current_date = ending_at - 15.days

        travel_to(current_date) do
          expect do
            described_class.perform_now
          end
            .to have_enqueued_job(SendWebhookJob)
            .with('subscription.reaching_termination', Subscription)
            .exactly(0).times
        end
      end
    end
  end
end
