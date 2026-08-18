# frozen_string_literal: true

module LifetimeUsages
  class CalculateService < BaseService
    Result = BaseResult[:lifetime_usage]

    def initialize(lifetime_usage:, current_usage: nil)
      @lifetime_usage = lifetime_usage
      @current_usage = current_usage
      super
    end

    def call
      result.lifetime_usage = lifetime_usage

      # clear boolean flags without recalculating if the subscription is not active.
      if !lifetime_usage.subscription.active?
        lifetime_usage.update!(recalculate_current_usage: false, recalculate_invoiced_usage: false)
        return result
      end

      # The open-period pay-in-advance amount is subtracted from the current usage, so the invoiced
      # side must be refreshed in the same run: otherwise the subtraction removes fees that the
      # cached invoiced column does not contain yet, and both counters stop describing one snapshot.
      if lifetime_usage.recalculate_invoiced_usage || pay_in_advance_invoiced_amount_cents.positive?
        lifetime_usage.invoiced_usage_amount_cents = calculate_invoiced_usage_amount_cents
        lifetime_usage.recalculate_invoiced_usage = false
        lifetime_usage.invoiced_usage_amount_refreshed_at = Time.current
      end

      lifetime_usage.current_usage_amount_cents = calculate_current_usage_amount_cents
      lifetime_usage.recalculate_current_usage = false
      lifetime_usage.current_usage_amount_refreshed_at = Time.current

      lifetime_usage.save!

      result
    end

    private

    delegate :subscription, :organization, to: :lifetime_usage

    def calculate_invoiced_usage_amount_cents
      subscription_ids = organization.subscriptions
        .where(external_id: subscription.external_id, subscription_at: subscription.subscription_at)
        .where(canceled_at: nil)
        .select(:id)

      invoice_ids = organization.invoices.subscription
        .where(status: %i[finalized draft])
        .joins(:invoice_subscriptions)
        .where(invoice_subscriptions: {subscription_id: subscription_ids})
        .select(:id)

      organization.fees.charge.where(invoice_id: invoice_ids).sum(:amount_cents)
    end

    def calculate_current_usage_amount_cents
      [current_usage.amount_cents - pay_in_advance_invoiced_amount_cents, 0].max
    end

    # Usage of an invoiceable pay-in-advance charge is invoiced immediately, inside the still-open
    # period, so it lands in the invoiced counter while the current usage still reports it. The fee
    # carries the open-period boundaries in its properties, the invoice_subscription does not.
    def pay_in_advance_invoiced_amount_cents
      @pay_in_advance_invoiced_amount_cents ||= organization.fees.charge
        .where(subscription_id: subscription.id, pay_in_advance: true)
        .joins(:invoice)
        .merge(Invoice.subscription.where(status: %i[finalized draft]))
        .where("(fees.properties->>'charges_to_datetime')::timestamptz > ?", Time.current)
        .sum(:amount_cents)
    end

    def current_usage
      @current_usage ||= Invoices::CustomerUsageService.call(
        customer: subscription.customer,
        subscription: subscription,
        apply_taxes: false,
        with_cache: true
      ).usage
    end

    attr_accessor :lifetime_usage
  end
end
