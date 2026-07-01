# frozen_string_literal: true

module BillingCycles
  # Processor lane: turns the pending billing cycles for one (subscription, billing_at)
  # into a single invoice. It reuses Lago's generic invoice machinery — the generating
  # invoice, amount/tax computation and finalization all operate on Invoice/Fee and
  # don't care that the fees came from the new product-catalog engine. The only new
  # step is building the fees, one per cycle, via ComputeFeeService.
  #
  # The cycles are the outbox: the whole run is wrapped in a transaction, so a failure
  # rolls back and leaves the cycles pending for a retry.
  class ProcessService < BaseService
    Result = BaseResult[:invoice]

    def initialize(subscription:, billing_at:)
      @subscription = subscription
      @billing_at = billing_at
      super
    end

    def call
      # Serialise concurrent runs for the same (subscription, billing_at): two clock
      # scans can both enqueue a ProcessJob for the same pair while its cycles are still
      # pending. The lock + loading the pending cycles inside it means the loser sees an
      # empty set and no-ops, instead of emitting a duplicate invoice.
      subscription.with_advisory_lock("billing_cycle_process_#{subscription.id}_#{billing_at.to_i}") do
        process
      end

      result
    end

    private

    attr_reader :subscription, :billing_at
    attr_accessor :invoice

    def process
      return if cycles.empty?

      ActiveRecord::Base.transaction do
        create_generating_invoice
        build_fees
        Invoices::ComputeAmountsFromFees.call!(invoice:)
        invoice.save!
        Invoices::TransitionToFinalStatusService.call(invoice:)
        mark_cycles_done
      end

      result.invoice = invoice
    end

    def cycles
      @cycles ||= BillingCycle.pending.where(subscription:, billing_at:).to_a
    end

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer: subscription.customer,
        billing_entity: subscription.billing_entity || subscription.customer.billing_entity,
        invoice_type: :subscription,
        invoicing_reason: :subscription_periodic,
        currency: subscription.plan.amount_currency,
        datetime: billing_at
      ) do |generating_invoice|
        Invoices::CreateInvoiceSubscriptionService
          .call(invoice: generating_invoice, subscriptions: [subscription], timestamp: billing_at.to_i, invoicing_reason: :subscription_periodic)
          .raise_if_error!
      end
      invoice_result.raise_if_error!

      self.invoice = invoice_result.invoice
    end

    def build_fees
      cycles.each do |cycle|
        fee = BillingCycles::ComputeFeeService.call!(billing_cycle: cycle).fee
        fee.invoice = invoice
        fee.billing_entity = invoice.billing_entity
        fee.save!
      end
      invoice.fees.reload
    end

    def mark_cycles_done
      cycles.each { |cycle| cycle.update!(status: :done, invoice:) }
    end
  end
end
