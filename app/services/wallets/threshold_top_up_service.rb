# frozen_string_literal: true

module Wallets
  class ThresholdTopUpService < BaseService
    Result = BaseResult

    BURST_TOP_UPS = 3
    BURST_WINDOW = 10.minutes
    DAILY_TOP_UPS = ENV.fetch("LAGO_WALLET_MAX_AUTOMATIC_TOP_UPS_PER_DAY", 25).to_i
    DAILY_WINDOW = 24.hours

    def initialize(wallet:)
      @wallet = wallet
      super
    end

    def call
      return result if rule.nil?
      return result if wallet.credits_ongoing_balance > rule.threshold_credits
      return result if (pending_transactions_amount + wallet.credits_ongoing_balance) > rule.threshold_credits

      daily_top_ups = top_ups_since(DAILY_WINDOW)
      if daily_top_ups >= DAILY_TOP_UPS
        report("Automatic wallet top-up daily limit reached", count: daily_top_ups)
        return result
      end

      burst_top_ups = top_ups_since(BURST_WINDOW)
      if burst_top_ups >= BURST_TOP_UPS
        report("Automatic wallet top-up burst", count: burst_top_ups)
      end

      params = {
        wallet_id: wallet.id,
        paid_credits: rule.compute_paid_credits(ongoing_balance: wallet.credits_ongoing_balance).to_s,
        granted_credits: rule.compute_granted_credits.to_s,
        source: :threshold,
        invoice_requires_successful_payment: rule.invoice_requires_successful_payment?,
        metadata: rule.transaction_metadata,
        name: rule.transaction_name,
        ignore_paid_top_up_limits: rule.ignore_paid_top_up_limits?,
        purchase_order_number: rule.resolved_purchase_order_number
      }

      params[:invoice_custom_section] = rule.invoice_custom_section_params if rule.invoice_custom_section_params

      WalletTransactions::CreateJob.set(wait: 2.seconds).perform_later(
        organization_id: wallet.organization.id,
        params:,
        unique_transaction: true
      )

      result
    end

    private

    attr_reader :wallet

    def rule
      @rule ||= wallet.recurring_transaction_rules.active.where(trigger: :threshold).first
    end

    def pending_transactions_amount
      @pending_transactions_amount ||= wallet.wallet_transactions.pending.sum(:amount)
    end

    # Counts charges, not rows: outbound movements and granted-only top-ups cost the
    # customer nothing and must not push a wallet towards the ceiling.
    def top_ups_since(window)
      wallet.wallet_transactions.threshold.inbound.where(created_at: window.ago..).count
    end

    def report(message, count:)
      context = {wallet_id: wallet.id, organization_id: wallet.organization_id, top_ups: count}

      # Sentry does nothing without a DSN, which is the common self-hosted setup, so the
      # log line is what guarantees a refusal always leaves a trace somewhere.
      Rails.logger.warn("#{message} #{context.map { |k, v| "#{k}=#{v}" }.join(" ")}")
      Sentry.capture_message(message, level: :warning, extra: context)
    end
  end
end
