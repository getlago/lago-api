# frozen_string_literal: true

module Customers
  class RefreshWalletsService < BaseService
    Result = BaseResult[:usage_amount_cents, :wallets, :allocation_rules]

    def initialize(customer:, include_generating_invoices: false)
      @customer = customer
      @include_generating_invoices = include_generating_invoices

      super
    end

    def call
      usage_amount_cents = customer.active_subscriptions.map do |subscription|
        invoice = ::Invoices::CustomerUsageService.call!(customer:, subscription:).invoice

        billed_progressive_invoice_subscriptions = ::Subscriptions::ProgressiveBilledAmount
          .call(subscription:, include_generating_invoices:)
          .invoice_subscriptions

        {
          billed_progressive_invoice_subscriptions:,
          invoice:,
          subscription:
        }
      end

      @allocation_rules = Wallets::BuildAllocationRulesService.call!(customer:).allocation_rules

      usage_fees = usage_amount_cents.flat_map { |usage| usage[:invoice].fees }
      draft_invoice_fees = customer.invoices.draft.where.not(total_amount_cents: 0).includes(fees: :charge).flat_map(&:fees)
      progressive_billing_fees = usage_amount_cents.flat_map { |usage| usage[:billed_progressive_invoice_subscriptions].flat_map { it.invoice.fees } }
      pay_in_advance_fees = usage_amount_cents.flat_map { |usage| usage[:invoice].fees.select { |f| f.charge.pay_in_advance? } }

      wallets_to_process = customer.wallets.active.includes(:recurring_transaction_rules)
      wallets_to_process.find_in_batches(batch_size: 100) do |wallets|
        wallets.each do |wallet|
          Wallets::Balance::RefreshOngoingUsageService.call!(
            wallet:,
            usage_amount_cents:,
            skip_single_wallet_update: true,
            current_usage_fees: find_fees_for_wallet(wallet, usage_fees),
            draft_invoices_fees: find_fees_for_wallet(wallet, draft_invoice_fees),
            progressive_billing_fees: find_fees_for_wallet(wallet, progressive_billing_fees),
            pay_in_advance_fees: find_fees_for_wallet(wallet, pay_in_advance_fees)
          )
        end
      end
      wallets_to_process.update_all(last_ongoing_balance_sync_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      customer.update!(awaiting_wallet_refresh: false)

      result.usage_amount_cents = usage_amount_cents
      result.allocation_rules = allocation_rules
      result.wallets = customer.wallets.active.reload
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :customer, :include_generating_invoices, :allocation_rules

    def find_fees_for_wallet(wallet, fees)
      fee_targeting_wallets_enabled = customer.organization.events_targeting_wallets_enabled?
      applicable_fees = []
      fees.each do |fee|
        if fee_targeting_wallets_enabled && fee.charge&.accepts_target_wallet && fee&.grouped_by&.dig("target_wallet_code").present?
          targeted_wallet = customer.wallets.active.where(code: fee.grouped_by["target_wallet_code"]).ids.first
          if targeted_wallet
            applicable_fees << fee if targeted_wallet == wallet.id
            next
          end
        end

        applicable_wallet = Wallets::FindApplicableOnFeesService
                               .call!(allocation_rules: allocation_rules, fee:, customer_id: customer.id, fee_targeting_wallets_enabled:)
                               .top_priority_wallet
        applicable_fees << fee if applicable_wallet == wallet.id
      end
    end
  end
end
