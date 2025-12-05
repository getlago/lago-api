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

        progressive_billed_total = ::Subscriptions::ProgressiveBilledAmount
          .call(subscription:, include_generating_invoices:)
          .total_billed_amount_cents

        {
          total_usage_amount_cents: invoice.total_amount_cents,
          billed_usage_amount_cents: billed_usage_amount_cents(invoice, progressive_billed_total),
          invoice:,
          subscription:
        }
      end

      allocation_rules = Wallets::BuildAllocationRulesService.call!(customer:).allocation_rules

      customer.wallets.active.find_each do |wallet|
        Wallets::Balance::RefreshOngoingUsageService.call!(
          wallet:,
          usage_amount_cents:,
          allocation_rules:
        )
      end

      result.usage_amount_cents = usage_amount_cents
      result.allocation_rules = allocation_rules
      result.wallets = customer.wallets.active.reload
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :customer, :include_generating_invoices

    def billed_usage_amount_cents(invoice, progressive_billed_total)
      paid_in_advance_fees = invoice.fees.select { |f| f.charge.pay_in_advance? && f.charge.invoiceable? }
      progressive_billed_total +
        # Invoice that is returned from CustomerUsageService includes the taxes in total_usage
        # so if the fees ae already paid, we should exclude fees AND their taxes
        paid_in_advance_fees.sum(&:amount_cents) +
        paid_in_advance_fees.sum(&:taxes_amount_cents)
    end
  end
end
