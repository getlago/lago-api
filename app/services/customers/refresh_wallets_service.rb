# frozen_string_literal: true

module Customers
  class RefreshWalletsService < BaseService
    Result = BaseResult[:wallets]

    def initialize(customer:, include_generating_invoices: false)
      @customer = customer
      @include_generating_invoices = include_generating_invoices

      super
    end

    def call
      wallet_allocations = Wallets::Balance::AllocateOngoingUsageByWalletsService.call!(
        customer:,
        wallets: all_wallets,
        current_usage_fees:,
        draft_invoices_fees:,
        progressive_billing_fees:,
        pay_in_advance_fees:
      ).wallet_allocations

      # The cascade makes every wallet's allocation depend on the others' balances, so all
      # wallets must be persisted together; refreshing a subset would leave the rest stale.
      all_wallets.each do |wallet|
        Wallets::Balance::RefreshOngoingUsageService.call!(
          wallet:,
          ongoing_usage_amount_cents: wallet_allocations[wallet],
          skip_single_wallet_update: true
        )
      end

      Wallet.where(id: all_wallets.map(&:id)).update_all(last_ongoing_balance_sync_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      customer.update!(awaiting_wallet_refresh: false)

      result.wallets = customer.wallets.active.reload
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :customer, :include_generating_invoices

    def all_wallets
      @all_wallets ||= customer.wallets.active.includes(:recurring_transaction_rules, :wallet_targets).in_application_order.to_a
    end

    def current_usage_fees
      @current_usage_fees ||= subscription_usages.flat_map { |usage| usage[:invoice].fees }
    end

    # pay-in-advance fees are a subset of the current usage fees, so filter rather than re-walk.
    def pay_in_advance_fees
      current_usage_fees.select { |fee| fee.charge.pay_in_advance? }
    end

    def draft_invoices_fees
      customer.invoices.draft.where.not(total_amount_cents: 0).includes(fees: :charge).flat_map(&:fees)
    end

    def progressive_billing_fees
      subscription_usages.flat_map { |usage| usage[:billed_progressive_invoice_subscriptions].flat_map { it.invoice.fees.includes(:charge) } }
    end

    # One entry per active subscription: its current-usage invoice and the progressively
    # billed invoice subscriptions used to net already-billed amounts out of ongoing usage.
    def subscription_usages
      @subscription_usages ||= customer.active_subscriptions.map do |subscription|
        invoice = ::Invoices::CustomerUsageService.call!(customer:, subscription:, usage_filters: UsageFilters::WITHOUT_PRESENTATION_FILTER).invoice

        billed_progressive_invoice_subscriptions = ::Subscriptions::ProgressiveBilledAmount
          .call(subscription:, include_generating_invoices:)
          .invoice_subscriptions

        {billed_progressive_invoice_subscriptions:, invoice:, subscription:}
      end
    end
  end
end
