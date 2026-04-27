# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::Payment::ResolveService do
  subject(:result) { described_class.call(subscription:, invoice:, payment_status:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true) }
  let(:subscription) { create(:subscription, :incomplete, organization:, customer:, plan:) }
  let(:rule) { create(:subscription_activation_rule, subscription:, status: "pending") }
  let(:invoice) do
    create(:invoice, organization:, customer:, status: :open, invoice_type: :subscription,
      total_amount_cents: 100, fees_amount_cents: 100)
  end
  let(:payment_status) { :failed }

  before do
    rule
    create(:invoice_subscription, invoice:, subscription:)
  end

  context "when subscription is not incomplete" do
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }

    it "returns early without changes" do
      result

      expect(rule.reload.status).to eq("pending")
      expect(invoice.reload.status).to eq("open")
    end
  end

  context "when invoice is not open" do
    before { invoice.update!(status: :finalized) }

    it "returns early without changes" do
      result

      expect(rule.reload.status).to eq("pending")
      expect(subscription.reload).to be_incomplete
    end
  end

  context "when invoice is not a subscription invoice" do
    let(:invoice) do
      create(:invoice, :credit, organization:, customer:, status: :open,
        total_amount_cents: 100, fees_amount_cents: 100)
    end

    it "returns early without changes" do
      result

      expect(rule.reload.status).to eq("pending")
      expect(subscription.reload).to be_incomplete
    end
  end

  context "when payment_status is succeeded" do
    let(:payment_status) { :succeeded }

    it "marks the activation rule as satisfied" do
      result

      expect(rule.reload.status).to eq("satisfied")
    end

    it "finalizes the invoice" do
      result

      expect(invoice.reload.status).to eq("finalized")
    end

    it "activates the subscription" do
      freeze_time do
        result

        expect(subscription.reload).to be_active
        expect(subscription.activated_at).to eq(Time.current)
      end
    end

    it "sends a subscription.started webhook" do
      result

      expect(SendWebhookJob).to have_been_enqueued.with("subscription.started", subscription)
    end

    context "when subscription is already active (idempotency)" do
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }

      it "returns early without changes" do
        result

        expect(rule.reload.status).to eq("pending")
        expect(invoice.reload.status).to eq("open")
      end
    end
  end

  context "when payment_status is failed" do
    let(:payment_status) { :failed }

    it "marks the activation rule as failed" do
      result

      expect(rule.reload.status).to eq("failed")
    end

    it "closes the invoice" do
      result

      expect(invoice.reload.status).to eq("closed")
    end

    it "cancels the subscription with payment_failed reason" do
      result

      expect(subscription.reload).to be_canceled
      expect(subscription.cancelation_reason).to eq("payment_failed")
    end

    it "sends a subscription.canceled webhook" do
      result

      expect(SendWebhookJob).to have_been_enqueued.with("subscription.canceled", subscription)
    end
  end

  context "when payment succeeds late on a canceled subscription with closed invoice" do
    let(:subscription) { create(:subscription, :canceled, organization:, customer:, plan:) }
    let(:invoice) do
      create(:invoice, organization:, customer:, status: :closed, invoice_type: :subscription,
        total_amount_cents: 100, fees_amount_cents: 100)
    end
    let(:payment_status) { :succeeded }

    it "enqueues a refund job for the invoice" do
      result

      expect(Payments::RefundJob).to have_been_enqueued.with(invoice)
    end

    it "does not change the rule status" do
      result

      expect(rule.reload.status).to eq("pending")
    end

    it "does not finalize the invoice" do
      result

      expect(invoice.reload.status).to eq("closed")
    end

    it "does not reactivate the subscription" do
      result

      expect(subscription.reload).to be_canceled
    end
  end

  context "when payment fails late on a canceled subscription with closed invoice" do
    let(:subscription) { create(:subscription, :canceled, organization:, customer:, plan:) }
    let(:invoice) do
      create(:invoice, organization:, customer:, status: :closed, invoice_type: :subscription,
        total_amount_cents: 100, fees_amount_cents: 100)
    end
    let(:payment_status) { :failed }

    it "does not enqueue a refund job" do
      result

      expect(Payments::RefundJob).not_to have_been_enqueued
    end

    it "does not change the rule status" do
      result

      expect(rule.reload.status).to eq("pending")
    end
  end
end
