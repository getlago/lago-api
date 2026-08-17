# frozen_string_literal: true

module Subscriptions
  # Tears down an incomplete (payment-gated) subscription: the activation rule
  # is rejected with the given status, the gating invoice is closed and every
  # resource it consumed is given back to the customer.
  class CancelService < BaseService
    Result = BaseResult[:subscription]

    def initialize(subscription:, rule_status:, cancellation_reason:)
      @subscription = subscription
      @rule_status = rule_status
      @cancellation_reason = cancellation_reason
      super
    end

    def call
      subscription.with_lock do
        # Race protection: a payment webhook may resolve the subscription
        # concurrently. If it already did so by the time we acquired the
        # lock, bail.
        next unless subscription.incomplete?

        payment_rule = subscription.activation_rules.payment.sole
        ActivationRules::Payment::EvaluateService.call!(rule: payment_rule, status: rule_status)

        invoice = subscription.invoices.open.subscription.sole
        invoice.closed!

        ActivationRules::ResolveSubscriptionStatusService.call!(subscription:)
        subscription.update!(cancellation_reason:)

        enqueue_psp_cancel(invoice)
        enqueue_recredit_jobs(invoice)
      end

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription, :rule_status, :cancellation_reason

    def enqueue_recredit_jobs(invoice)
      invoice.credits.coupon_kind.find_each do |credit|
        AppliedCoupons::RecreditJob.perform_after_commit(credit)
      end

      invoice.credits.credit_note_kind.find_each do |credit|
        CreditNotes::RecreditJob.perform_after_commit(credit)
      end

      invoice.wallet_transactions.outbound.find_each do |wallet_transaction|
        WalletTransactions::RecreditJob.perform_after_commit(wallet_transaction)
      end
    end

    def enqueue_psp_cancel(invoice)
      # A partial unique index on payments guarantees at most one
      # provider payment in (pending, processing) per invoice, and the
      # payment-gated lifecycle ensures the first failure already
      # cancels the subscription before any retry could create a second
      # one — so this find returns the single live payment when present.
      payment = invoice.payments
        .where(payable_payment_status: %w[pending processing])
        .first
      return unless payment

      PaymentProviders::CancelPaymentJob.perform_after_commit(payment)
    end
  end
end
