# frozen_string_literal: true

module Invoices
  class CreateAdvanceChargesInvoiceSubscriptionService < BaseService
    Result = BaseResult

    def initialize(invoice:, timestamp:, subscriptions_with_fees:, all_subscriptions:)
      @invoice = invoice
      @timestamp = timestamp
      @subscriptions_with_fees = subscriptions_with_fees
      @all_subscriptions = all_subscriptions

      super
    end

    # Since the `advance_charges` invoice only have charges by design,
    # we apply the `charges_(from|to)_date for both charges and subscriptions period
    # See https://github.com/getlago/lago-api/pull/3327 for details
    def call
      latest_subscription = all_subscriptions.max_by(&:started_at)
      boundaries = calculate_boundaries(latest_subscription)

      return skip_invalid_boundaries(latest_subscription, boundaries) unless charge_boundaries_valid?(boundaries)

      subscriptions_with_fees.each do |subscription|
        invoice.invoice_subscriptions << InvoiceSubscription.create!(
          organization: subscription.organization,
          invoice:,
          subscription:,
          timestamp:,
          from_datetime: boundaries[:from],
          to_datetime: boundaries[:to],
          charges_from_datetime: boundaries[:from],
          charges_to_datetime: boundaries[:to],
          recurring: false,
          invoicing_reason: :in_advance_charge_periodic
        )
      end

      result
    end

    private

    attr_reader :invoice, :timestamp, :subscriptions_with_fees, :all_subscriptions

    def calculate_boundaries(subscription)
      date_service = Subscriptions::DatesService.new_instance(
        subscription,
        boundaries_billing_at(subscription),
        current_usage: false
      )

      {
        from: date_service.charges_from_datetime,
        to: date_service.charges_to_datetime
      }
    end

    # NOTE: A subscription already terminated at `timestamp` has a charges period that ended on its
    #       termination date. It can still be re-expanded into a much later billing cycle (see
    #       Invoices::AdvanceChargesService#subscriptions), and computing its boundaries from that cycle's
    #       timestamp then yields a period starting after it ended, because `charges_to_datetime` stays
    #       capped at `terminated_at`.
    #       The termination flow already bills non-invoiceable fees on `terminated_at`, so we do the same.
    def boundaries_billing_at(subscription)
      return timestamp unless subscription.terminated_at?(timestamp)

      subscription.terminated_at
    end

    # NOTE: Unlike Invoices::CalculateFeesService, blank boundaries are not invalid here: yearly plans
    #       legitimately produce no charges boundaries, and their already-paid fees must still be invoiced.
    def charge_boundaries_valid?(boundaries)
      return true if boundaries[:from].blank? || boundaries[:to].blank?

      boundaries[:from] <= boundaries[:to]
    end

    # Defer the fees rather than stamping an invalid period: leaving them with `invoice_id: nil` makes the
    # next billing cycle retry them, and the invoice is rolled back by the caller when no fee is attached.
    def skip_invalid_boundaries(subscription, boundaries)
      message = "Invoices::CreateAdvanceChargesInvoiceSubscriptionService skipped: invalid charges boundaries"
      context = {
        organization_id: invoice.organization_id,
        invoice_id: invoice.id,
        subscription_id: subscription.id,
        subscription_status: subscription.status,
        charges_from_datetime: boundaries[:from],
        charges_to_datetime: boundaries[:to],
        timestamp:
      }

      Rails.logger.warn("#{message} #{context.map { |k, v| "#{k}=#{v}" }.join(" ")}")

      result
    end
  end
end
