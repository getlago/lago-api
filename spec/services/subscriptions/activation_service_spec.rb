# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationService do
  describe "#call" do
    subject(:result) { described_class.call(subscription:, invoice:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, :activating, customer:, plan:, organization:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:finalize_result) { BaseResult.new }

    before do
      allow(Invoices::FinalizeService).to receive(:call!).and_return(finalize_result)
      allow(SendWebhookJob).to receive(:perform_later)
      allow(Utils::ActivityLog).to receive(:produce)
      allow(Invoices::GenerateDocumentsJob).to receive(:perform_later)
      allow(Utils::SegmentTrack).to receive(:invoice_created)
    end

    it "transitions the subscription to active" do
      expect { result }.to change { subscription.reload.status }.from("activating").to("active")
    end

    it "returns a successful result with the subscription" do
      expect(result).to be_success
      expect(result.subscription).to eq(subscription)
    end

    it "finalizes the invoice" do
      result

      expect(Invoices::FinalizeService).to have_received(:call!).with(invoice:)
    end

    it "updates the invoice issuing_date and payment_due_date" do
      freeze_time do
        expected_date = Time.current.in_time_zone(customer.applicable_timezone).to_date

        result

        expect(invoice.issuing_date).to eq(expected_date)
        expect(invoice.payment_due_date).to eq(expected_date + invoice.net_payment_term.days)
      end
    end

    it "enqueues a SendWebhookJob" do
      result

      expect(SendWebhookJob).to have_received(:perform_later).with("subscription.started", subscription)
    end

    it "produces an activity log" do
      result

      expect(Utils::ActivityLog).to have_produced("subscription.started").with(subscription)
    end

    context "when subscription is not activating" do
      let(:subscription) { create(:subscription, customer:, plan:, organization:) }

      it "returns early without changing the subscription" do
        expect { result }.not_to change { subscription.reload.status }
      end

      it "does not finalize the invoice" do
        result

        expect(Invoices::FinalizeService).not_to have_received(:call!)
      end

      it "does not enqueue a SendWebhookJob" do
        result

        expect(SendWebhookJob).not_to have_received(:perform_later)
      end
    end

    context "when there is a previous subscription" do
      let(:previous_subscription) { create(:subscription, customer:, plan:, organization:) }
      let(:subscription) do
        create(:subscription, :activating, customer:, plan:, organization:, previous_subscription:)
      end
      let(:terminate_result) { BaseResult.new }

      before do
        allow(Subscriptions::TerminateService).to receive(:call).and_return(terminate_result)
      end

      it "terminates the previous subscription with upgrade flag" do
        result

        expect(Subscriptions::TerminateService).to have_received(:call).with(
          subscription: previous_subscription,
          upgrade: true
        )
      end
    end

    context "when there is no previous subscription" do
      it "does not call the terminate service" do
        allow(Subscriptions::TerminateService).to receive(:call)

        result

        expect(Subscriptions::TerminateService).not_to have_received(:call)
      end
    end

    describe "invoice side effects" do
      it "sends invoice.created webhook" do
        result

        expect(SendWebhookJob).to have_received(:perform_later).with("invoice.created", invoice)
      end

      it "produces an invoice activity log" do
        result

        expect(Utils::ActivityLog).to have_produced("invoice.created").with(invoice)
      end

      it "generates documents" do
        result

        expect(Invoices::GenerateDocumentsJob).to have_received(:perform_later).with(invoice:, notify: false)
      end

      it "tracks the segment event" do
        result

        expect(Utils::SegmentTrack).to have_received(:invoice_created).with(invoice)
      end

      context "when invoice should sync to integrations" do
        before do
          allow(invoice).to receive(:should_sync_invoice?).and_return(true)
          allow(invoice).to receive(:should_sync_hubspot_invoice?).and_return(true)
          allow(Integrations::Aggregator::Invoices::CreateJob).to receive(:perform_later)
          allow(Integrations::Aggregator::Invoices::Hubspot::CreateJob).to receive(:perform_later)
        end

        it "enqueues integration sync jobs" do
          result

          expect(Integrations::Aggregator::Invoices::CreateJob).to have_received(:perform_later).with(invoice:)
          expect(Integrations::Aggregator::Invoices::Hubspot::CreateJob).to have_received(:perform_later).with(invoice:)
        end
      end
    end
  end
end
