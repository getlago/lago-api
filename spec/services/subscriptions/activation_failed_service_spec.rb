# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationFailedService do
  subject(:result) { described_class.call(subscription:, invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, :activating, customer:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  before do
    allow(Subscriptions::Payments::CancelService).to receive(:call)
  end

  describe "#call" do
    it "terminates the subscription" do
      freeze_time do
        result

        expect(result).to be_success
        expect(result.subscription).to eq(subscription)
        expect(subscription.reload).to be_terminated
        expect(subscription.terminated_at).to be_within(1.second).of(Time.current)
      end
    end

    it "clears activation fields" do
      result

      subscription.reload
      expect(subscription.started_at).to be_nil
      expect(subscription.activating_at).to be_nil
    end

    it "sets the invoice status to closed" do
      result

      expect(invoice.reload.status).to eq("closed")
    end

    it "calls Subscriptions::Payments::CancelService after commit" do
      result

      expect(Subscriptions::Payments::CancelService).to have_received(:call).with(invoice:)
    end

    it "enqueues a SendWebhookJob after commit" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob)
        .with("subscription.activation_failed", subscription)
    end

    it "produces an activity log after commit" do
      result

      expect(Utils::ActivityLog).to have_produced("subscription.activation_failed").with(subscription)
    end

    context "when subscription is not activating" do
      let(:subscription) { create(:subscription, customer:) }

      it "returns early without changes" do
        result

        expect(result).to be_success
        expect(result.subscription).to be_nil
        expect(subscription.reload).to be_active
      end

      it "does not update the invoice" do
        expect { result }.not_to change { invoice.reload.status }
      end

      it "does not call Subscriptions::Payments::CancelService" do
        result

        expect(Subscriptions::Payments::CancelService).not_to have_received(:call)
      end

      it "does not enqueue a SendWebhookJob" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)
      end
    end
  end
end
