# frozen_string_literal: true

module EventDestinations
  # What each wallet absorbed per billable metric for a subscription's usage since from_datetime:
  # what the latest refresh allocates to it now, plus what billing charged to it on the invoices of
  # that period. Usage is attributed to wallets in proportion to these amounts.
  class WalletAmountsService < BaseService
    Result = BaseResult[:amounts]

    def initialize(subscription:, active_wallets:, from_datetime:)
      @subscription = subscription
      @active_wallets = active_wallets
      @from_datetime = from_datetime

      super
    end

    def call
      amounts = Hash.new { |hash, billable_metric_id| hash[billable_metric_id] = Hash.new(0) }

      active_wallets.each do |wallet|
        wallet.ongoing_billable_metric_amounts.each { |billable_metric_id, cents| amounts[billable_metric_id][wallet.id] += cents }
      end

      billed_amounts.each { |(billable_metric_id, wallet_id), cents| amounts[billable_metric_id][wallet_id] += cents }

      result.amounts = amounts
      result
    end

    private

    attr_reader :subscription, :active_wallets, :from_datetime

    # Terminated wallets are included: expiring credits end up in terminated wallets, and what they
    # paid is still part of the subscription's history. Voided invoices are not, since voiding gives
    # the credits back.
    def billed_amounts
      WalletTransaction
        .outbound
        .where.not(billable_metric_amounts: nil)
        .joins(:wallet, invoice: :invoice_subscriptions)
        .where(wallets: {customer_id: subscription.customer_id})
        .where(invoice_subscriptions: {subscription_id: subscription.id, charges_from_datetime: from_datetime..})
        .merge(Invoice.where.not(status: :voided))
        .joins("CROSS JOIN LATERAL jsonb_each_text(wallet_transactions.billable_metric_amounts) AS amounts(billable_metric_id, cents)")
        .group("amounts.billable_metric_id", "wallet_transactions.wallet_id")
        .sum("amounts.cents::bigint")
    end
  end
end
