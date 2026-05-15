# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::ExpireService do
  # TODO: remove after the dispatcher PR adding PaymentProviders::CancelPaymentJob is merged
  class PaymentProviders::CancelPaymentJob < ApplicationJob; end

  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true) }
  let(:subscription) { create(:subscription, :incomplete, customer:, organization:, plan:) }
  let(:invoice) do
    create(:invoice, :open, customer:, organization:, invoice_type: :subscription)
  end

  before do
    create(:invoice_subscription, invoice:, subscription:)
  end

  context "when the subscription is incomplete with a pending payment rule" do
    let(:payment_rule) do
      create(:subscription_activation_rule, subscription:, organization:,
        status: "pending", timeout_hours: 48, expires_at: 1.hour.ago)
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

    it "marks the payment activation rule as expired" do
      result

      expect(payment_rule.reload).to be_expired
    end

    it "closes the open invoice" do
      result

      expect(invoice.reload).to be_closed
    end

    it "cancels the subscription with cancelation_reason: timeout" do
      result

      expect(subscription.reload).to be_canceled
      expect(subscription.cancelation_reason).to eq("timeout")
    end

    it "enqueues a PSP cancel job for the pending payment" do
      result

      expect(PaymentProviders::CancelPaymentJob).to have_been_enqueued.with(payment)
    end

    it "returns a successful result with the subscription" do
      expect(result).to be_success
      expect(result.subscription).to eq(subscription)
    end
  end

  context "when the subscription is no longer incomplete (resolved concurrently)" do
    let(:payment_rule) do
      create(:subscription_activation_rule, subscription:, organization:,
        status: "satisfied", timeout_hours: 48, expires_at: 1.hour.ago)
    end

    before do
      payment_rule
      subscription.update!(status: :active)
    end

    it "returns a successful result without mutating state" do
      result

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
      create(:subscription_activation_rule, subscription:, organization:,
        status: "pending", timeout_hours: 48, expires_at: 1.hour.ago)
    end

    before { payment_rule }

    it "still expires the rule and cancels the subscription" do
      result

      expect(payment_rule.reload).to be_expired
      expect(subscription.reload).to be_canceled
      expect(subscription.cancelation_reason).to eq("timeout")
      expect(invoice.reload).to be_closed
    end

    it "does not enqueue a PSP cancel job (nothing to cancel)" do
      result

      expect(PaymentProviders::CancelPaymentJob).not_to have_been_enqueued
    end
  end
end
