# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::TryActivateService do
  subject(:result) { described_class.call(subscription:, invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, :activating, customer:, plan:, organization:) }
  let(:invoice) { create(:invoice, :open, customer:, organization:) }

  describe "#call" do
    context "when all rules are satisfied" do
      before do
        create(:subscription_activation_rule, :satisfied, subscription:, organization:)
        allow(Invoices::FinalizeService).to receive(:call!).and_return(BaseService::Result.new)
        allow(SendWebhookJob).to receive(:perform_later)
        allow(Invoices::GenerateDocumentsJob).to receive(:perform_later)
        allow(Utils::ActivityLog).to receive(:produce)
      end

      it "finalizes the invoice" do
        result
        expect(Invoices::FinalizeService).to have_received(:call!).with(invoice:)
      end

      it "sends the invoice.created webhook" do
        result
        expect(SendWebhookJob).to have_received(:perform_later).with("invoice.created", invoice)
      end

      it "sends the subscription.started webhook" do
        result
        expect(SendWebhookJob).to have_received(:perform_later).with("subscription.started", subscription)
      end

      it "activates the subscription" do
        result
        expect(subscription.reload).to be_active
      end

      it "produces activity logs" do
        result
        expect(Utils::ActivityLog).to have_received(:produce).with(invoice, "invoice.created")
        expect(Utils::ActivityLog).to have_received(:produce).with(subscription, "subscription.started")
      end

      it "generates invoice documents" do
        result
        expect(Invoices::GenerateDocumentsJob).to have_received(:perform_later).with(invoice:)
      end
    end

    context "when there are still pending rules" do
      let!(:satisfied_rule) do
        create(:subscription_activation_rule, :satisfied, subscription:, organization:, rule_type: "payment_required")
      end

      before do
        # Simulate a second rule type that's still pending
        # For now, we only have payment_required, so we test with a pending rule
        satisfied_rule.update!(status: "pending")
      end

      it "does not activate the subscription" do
        result
        expect(subscription.reload).to be_activating
      end
    end
  end
end
