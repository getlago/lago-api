# frozen_string_literal: true

module BillingCycles
  # Consumer lane, scoped to ONE customer. Loads the customer's pending cycles, groups
  # them into invoices by the dimensions that can't share one invoice — billing date,
  # currency, billing entity, payment method (parity with the legacy
  # Subscriptions::OrganizationBillingService) plus the consolidate_invoice opt-out —
  # and turns each group into a single invoice (one invoice_subscription per subscription,
  # one fee per cycle).
  #
  # The per-customer advisory lock does two things: it stops two concurrent runs from
  # double-invoicing the same cycles, and it makes the run see the COMPLETE set (a
  # producer creates a customer's whole set in one transaction, so once visible it's
  # whole). Reuses Lago's generic invoice machinery; only fee-building is new.
  class ProcessService < BaseService
    Result = BaseResult[:invoices]

    def initialize(customer:)
      @customer = customer
      super
    end

    def call
      result.invoices = []

      customer.with_advisory_lock("billing_cycle_process_customer_#{customer.id}") do
        pending_cycles.group_by { |cycle| invoice_key(cycle) }.each_value do |cycles|
          result.invoices << build_invoice(cycles)
        end

        # Finalize inline (invoice numbering) in the same job — one job per invoice, like
        # the legacy BillSubscriptionJob, so no extra Sidekiq hop. Each finalize runs in
        # its OWN short transaction (invoice.finalized!), so the per-billing_entity
        # numbering lock is held briefly and a race raises a clean SequenceError that the
        # ProcessJob retries. Retry-safe: a failed finalize leaves the invoice `generating`,
        # and this reconcile re-finalizes it on the retry (it re-queries generating
        # invoices, so it doesn't re-create — the cycles are already `done`).
        finalize_generating_invoices
      end

      result
    end

    private

    attr_reader :customer

    def pending_cycles
      BillingCycle.pending.where(customer_id: customer.id).includes(subscription: :plan).to_a
    end

    # The dimensions that must NOT be mixed on one invoice. Subscriptions differing on
    # any of them split into separate invoices; consolidate_invoice=false forces its own.
    def invoice_key(cycle)
      subscription = cycle.subscription
      [
        billing_date(cycle),
        subscription.consolidate_invoice ? :shared : subscription.id,
        subscription.plan.amount_currency,
        subscription.billing_entity_id || customer.billing_entity_id,
        payment_method_key(subscription)
      ]
    end

    def billing_date(cycle)
      cycle.billing_at.in_time_zone(customer.applicable_timezone).to_date
    end

    # Effective payment method (parity with the legacy grouping): explicit wins, else the
    # customer default; only splits when the org has the feature enabled.
    def payment_method_key(subscription)
      return nil unless customer.organization.feature_flag_enabled?(:multiple_payment_methods)

      if subscription.payment_method_id.present?
        [subscription.payment_method_id, subscription.payment_method_type]
      elsif subscription.payment_method_type == "manual"
        [nil, "manual"]
      elsif customer.default_payment_method.present?
        [customer.default_payment_method.id, "provider"]
      else
        [nil, subscription.payment_method_type]
      end
    end

    def build_invoice(cycles)
      subscriptions = cycles.map(&:subscription).uniq
      billing_at = cycles.first.billing_at
      billing_entity = subscriptions.first.billing_entity || customer.billing_entity
      invoice = nil

      ActiveRecord::Base.transaction do
        invoice_result = Invoices::CreateGeneratingService.call(
          customer:,
          billing_entity:,
          invoice_type: :subscription,
          invoicing_reason: :subscription_periodic,
          currency: subscriptions.first.plan.amount_currency,
          datetime: billing_at
        ) do |generating_invoice|
          create_invoice_subscriptions(generating_invoice, cycles)
        end
        invoice_result.raise_if_error!
        invoice = invoice_result.invoice

        cycles.each do |cycle|
          fee = BillingCycles::ComputeFeeService.call!(billing_cycle: cycle).fee
          fee.invoice = invoice
          fee.billing_entity = invoice.billing_entity
          fee.save!
        end
        invoice.fees.reload

        Invoices::ComputeAmountsFromFees.call!(invoice:)
        invoice.save!
        cycles.each { |cycle| cycle.update!(status: :done, invoice:) }
      end

      invoice
    end

    # The billing_cycle already carries the exact period per item, so the new engine owns
    # its invoice_subscription link directly — one per subscription, boundaries spanning that
    # subscription's cycles. This replaces the legacy CreateInvoiceSubscriptionService, which
    # derives boundaries from a plan-level interval that product-catalog plans don't have
    # (their intervals live per rate card). Keeping the link is what wires the invoice into
    # subscription.invoices and the invoice PDF's subscription section.
    def create_invoice_subscriptions(invoice, cycles)
      cycles.group_by(&:subscription).each do |subscription, subscription_cycles|
        period_from = subscription_cycles.map(&:period_from).min
        period_to = subscription_cycles.map(&:period_to).max

        InvoiceSubscription.create!(
          organization: invoice.organization,
          invoice:,
          subscription:,
          from_datetime: period_from,
          to_datetime: period_to,
          charges_from_datetime: period_from,
          charges_to_datetime: period_to,
          recurring: true,
          invoicing_reason: :subscription_periodic
        )
      end
    end

    # Finalize every still-generating invoice this customer's cycles produced — this run's
    # plus any left generating by a failed finalize on a previous attempt. Re-querying
    # (not the built array) is what makes a job retry recover orphans without re-creating.
    def finalize_generating_invoices
      invoice_ids = BillingCycle
        .where(customer_id: customer.id, status: :done)
        .where.not(invoice_id: nil)
        .joins(:invoice)
        .where(invoices: {status: :generating})
        .distinct
        .pluck(:invoice_id)

      Invoice.where(id: invoice_ids).find_each do |invoice|
        Invoices::TransitionToFinalStatusService.call(invoice:)
      end
    end
  end
end
