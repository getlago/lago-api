# frozen_string_literal: true

module Wallets
  class ThresholdTopUpService < BaseService
    Result = BaseResult

    BURST_TOP_UPS = 3
    BURST_WINDOW = 10.minutes
    DECLINE_BACKOFF = 1.hour

    def initialize(wallet:, state_changed: true)
      @wallet = wallet
      @state_changed = state_changed
      super
    end

    def call
      return result unless state_changed
      return result if rule.nil?
      return result if wallet.reserved_for_expiration_invoice?
      return result if wallet.credits_ongoing_balance > rule.threshold_credits
      return result if (pending_transactions_amount + wallet.credits_ongoing_balance) > rule.threshold_credits

      paid_credits = rule.compute_paid_credits(
        ongoing_balance: wallet.credits_ongoing_balance,
        pending_credits: pending_transactions_amount
      )
      return result if paid_credits.positive? && backing_off_after_decline?
      return result if paid_credits.positive? && cannot_be_charged?

      burst_top_ups = top_ups_since(BURST_WINDOW)
      if burst_top_ups >= BURST_TOP_UPS
        report("Automatic wallet top-up burst", count: burst_top_ups)
      end

      params = {
        wallet_id: wallet.id,
        paid_credits: paid_credits.to_s,
        granted_credits: rule.compute_granted_credits.to_s,
        source: :threshold,
        invoice_requires_successful_payment: rule.invoice_requires_successful_payment?,
        metadata: rule.transaction_metadata,
        name: rule.transaction_name,
        ignore_paid_top_up_limits: rule.target? || rule.ignore_paid_top_up_limits?,
        purchase_order_number: rule.resolved_purchase_order_number
      }

      params[:invoice_custom_section] = rule.invoice_custom_section_params if rule.invoice_custom_section_params

      WalletTransactions::CreateJob.set(wait: 2.seconds).perform_later(
        organization_id: wallet.organization_id,
        params:,
        unique_transaction: true
      )

      result
    end

    private

    attr_reader :wallet, :state_changed

    delegate :customer, to: :wallet

    def rule
      @rule ||= wallet.recurring_transaction_rules.active.where(trigger: :threshold).first
    end

    def pending_transactions_amount
      @pending_transactions_amount ||= wallet.wallet_transactions.pending.sum(:credit_amount)
    end

    def backing_off_after_decline?
      last_decline_at = automatic_top_ups.failed.maximum(:failed_at)

      return false if last_decline_at.nil?
      return false if last_decline_at < DECLINE_BACKOFF.ago

      !paid_top_up_settled_since?(last_decline_at)
    end

    # A top-up that requires a successful payment and that nothing charges expires after an hour
    # (WalletTransactions::ExpirePendingService), and the rule would then start another one, endlessly.
    # Same conditions as Invoices::Payments::CreateService#should_process_payment?: the rule waits
    # until the customer can be charged. A rule or wallet paid by hand (manual) is left alone.
    def cannot_be_charged?
      return false unless rule.invoice_requires_successful_payment?
      return false if rule.payment_method_type == "manual" || wallet.payment_method_type == "manual"

      provider_customer = customer.provider_customer
      return true if provider_customer&.provider_customer_id.blank?
      return false if stripe_customer_balance_only?(provider_customer)
      return false if provider_payment_method_pending_backfill?(provider_customer)

      top_up_payment_method.nil?
    end

    def top_up_payment_method
      payment_method_id = rule.payment_method_id || wallet.payment_method_id
      return customer.payment_methods.find_by(id: payment_method_id) if payment_method_id

      customer.default_payment_method
    end

    # A Stripe bank transfer customer has no payment method, and is still charged through its cash balance
    def stripe_customer_balance_only?(provider_customer)
      provider_customer.is_a?(PaymentProviderCustomers::StripeCustomer) &&
        provider_customer.provider_payment_methods == ["customer_balance"]
    end

    def provider_payment_method_pending_backfill?(provider_customer)
      legacy_id = provider_customer.legacy_provider_method_id
      legacy_id.present? &&
        provider_customer.payment_methods.with_discarded.where(provider_method_id: legacy_id).none?
    end

    def paid_top_up_settled_since?(timestamp)
      wallet.wallet_transactions.inbound.purchased.settled.where(settled_at: timestamp..).exists?
    end

    def automatic_top_ups
      wallet.wallet_transactions.threshold.inbound.purchased
    end

    def top_ups_since(window)
      automatic_top_ups.where(created_at: window.ago..).count
    end

    def report(message, count:)
      context = {wallet_id: wallet.id, organization_id: wallet.organization_id, top_ups: count}

      Rails.logger.warn("#{message} #{context.map { |k, v| "#{k}=#{v}" }.join(" ")}")
      Sentry.capture_message(message, level: :warning, extra: context)
    end
  end
end
