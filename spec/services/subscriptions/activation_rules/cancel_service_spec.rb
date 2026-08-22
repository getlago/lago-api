# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::CancelService do
  subject(:result) { described_class.call(subscription:, rule_status:, cancellation_reason:) }

  let(:rule_status) { :declined }
  let(:cancellation_reason) { :manual }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true) }
  let(:subscription) { create(:subscription, :incomplete, customer:, organization:, plan:) }
  let(:invoice) { create(:invoice, :open, customer:, organization:, invoice_type: :subscription) }

  before do
    create(:invoice_subscription, invoice:, subscription:) if invoice
  end

  context "when the subscription is incomplete with a pending payment rule" do
    let(:payment_rule) do
      create(:subscription_activation_rule, subscription:, organization:, status: "pending", timeout_hours: 48)
    end
    let(:payment_provider) { create(:stripe_provider, organization:) }
    let(:payment) do
      create(:payment, payable: invoice, payment_provider:, organization:, customer:,
        provider_payment_id: "pi_test", payable_payment_status: :pending)
    end

    before do
      payment_rule
      payment
    end

    it "transitions the payment activation rule to the given status" do
      result

      expect(payment_rule.reload).to be_declined
    end

    it "closes the open invoice" do
      result

      expect(invoice.reload).to be_closed
    end

    it "cancels the subscription with the given cancellation reason" do
      result

      expect(subscription.reload).to be_canceled
      expect(subscription.cancellation_reason).to eq("manual")
    end

    it "enqueues a subscription.canceled webhook" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.canceled", subscription)
    end

    it "enqueues a PSP cancel job for the pending payment" do
      result

      expect(PaymentProviders::CancelPaymentJob).to have_been_enqueued.with(payment)
    end

    it "returns a successful result with the subscription" do
      expect(result).to be_success
      expect(result.subscription).to eq(subscription)
    end

    context "when the rule status and cancellation reason describe an activation timeout" do
      let(:rule_status) { :expired }
      let(:cancellation_reason) { :timeout }

      it "expires the rule and cancels the subscription with the timeout reason" do
        result

        expect(payment_rule.reload).to be_expired
        expect(subscription.reload).to be_canceled
        expect(subscription.cancellation_reason).to eq("timeout")
      end
    end

    context "when an applied-coupon credit was consumed" do
      let(:applied_coupon) { create(:applied_coupon, customer:, organization:, status: :terminated) }
      let(:credit) { create(:credit, invoice:, organization:, applied_coupon:) }

      before { credit }

      it "enqueues an AppliedCoupons::RecreditJob" do
        result

        expect(AppliedCoupons::RecreditJob).to have_been_enqueued.with(credit)
      end
    end

    context "when a credit-note credit was consumed" do
      let(:credit_note) { create(:credit_note, customer:, organization:, invoice:, credit_status: :available) }
      let(:credit) { create(:credit_note_credit, invoice:, organization:, credit_note:) }

      before { credit }

      it "enqueues a CreditNotes::RecreditJob" do
        result

        expect(CreditNotes::RecreditJob).to have_been_enqueued.with(credit)
      end
    end

    context "when an outbound wallet transaction was consumed" do
      let(:wallet) { create(:wallet, customer:, organization:) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet:, organization:, invoice:, transaction_type: :outbound) }

      before { wallet_transaction }

      it "enqueues a WalletTransactions::RecreditJob" do
        result

        expect(WalletTransactions::RecreditJob).to have_been_enqueued.with(wallet_transaction)
      end
    end
  end

  context "when the subscription is no longer incomplete (resolved concurrently)" do
    let(:payment_rule) do
      create(:subscription_activation_rule, subscription:, organization:, status: "satisfied", timeout_hours: 48)
    end

    before do
      payment_rule
      subscription.update!(status: :active)
    end

    it "returns a validation failure without mutating state" do
      result

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq({subscription: ["subscription_already_resolved"]})
      expect(subscription.reload).to be_active
      expect(payment_rule.reload).to be_satisfied
      expect(invoice.reload).to be_open
    end

    it "does not enqueue a PSP cancel job" do
      result

      expect(PaymentProviders::CancelPaymentJob).not_to have_been_enqueued
    end
  end

  context "when the open invoice has no pending or processing payments" do
    let(:payment_rule) do
      create(:subscription_activation_rule, subscription:, organization:, status: "pending", timeout_hours: 48)
    end

    before { payment_rule }

    it "still transitions the rule and cancels the subscription" do
      result

      expect(payment_rule.reload).to be_declined
      expect(subscription.reload).to be_canceled
      expect(subscription.cancellation_reason).to eq("manual")
      expect(invoice.reload).to be_closed
    end

    it "does not enqueue a PSP cancel job (nothing to cancel)" do
      result

      expect(PaymentProviders::CancelPaymentJob).not_to have_been_enqueued
    end
  end

  context "when a tax provider failure left the gating invoice failed" do
    let(:invoice) { create(:invoice, :failed, customer:, organization:, invoice_type: :subscription) }
    let(:applied_coupon) { create(:applied_coupon, customer:, organization:, status: :terminated) }
    let(:credit) { create(:credit, invoice:, organization:, applied_coupon:) }

    before do
      create(:subscription_activation_rule, subscription:, organization:, status: "pending", timeout_hours: 48)
      credit
    end

    it "closes the failed invoice and gives the coupon back" do
      result

      expect(result).to be_success
      expect(subscription.reload).to be_canceled
      expect(invoice.reload).to be_closed
      expect(AppliedCoupons::RecreditJob).to have_been_enqueued.with(credit)
    end
  end

  context "when the gating invoice has not been created yet" do
    let(:invoice) { nil }

    before do
      create(:subscription_activation_rule, subscription:, organization:, status: "pending", timeout_hours: 48)
    end

    it "returns a validation failure without mutating state" do
      result

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq({subscription: ["activation_invoice_not_ready"]})
      expect(subscription.reload).to be_incomplete
      expect(subscription.cancellation_reason).to be_nil
      expect(subscription.activation_rules.payment.sole).to be_pending
    end
  end
end
