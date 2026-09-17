# frozen_string_literal: true

class InvoiceSubscriptionsHelper
  SubscriptionWithFees = Data.define(:subscription, :invoice_subscription, :filtered_fees, :grouped_fees)

  def self.load_subscriptions_with_fees(invoice)
    invoice.sorted_subscriptions.map do |subscription|
      invoice_subscription = invoice.invoice_subscription(subscription.id)
      # Group all fees by their billing period (with eager loading and DB-level filtering to avoid N+1 queries)
      base_fees = invoice.subscription_fees(subscription.id)
        .includes(:true_up_parent_fee, :true_up_fee, :charge_filter, :presentation_breakdowns, charge: :billable_metric, fixed_charge: :add_on)
      # Always include subscription and commitment fees. Include fixed-charge and top-level charge fees
      # when their units or amount is positive. Also include zero-value charge fees that have a true-up child.
      displayable_fees = base_fees.where("fees.units > ? OR fees.amount_cents > ?", 0, 0)
      filtered_fees = base_fees
        .where(fee_type: [:subscription, :commitment])
        .or(displayable_fees.fixed_charge)
        .or(displayable_fees.charge.where(true_up_parent_fee: nil))
        .or(base_fees.charge.where(id: base_fees.charge.select(:true_up_parent_fee_id).where.not(true_up_parent_fee_id: nil)))
      grouped_fees = FeeBoundariesHelper.group_fees_by_billing_period(filtered_fees, invoice_subscription:)

      SubscriptionWithFees.new(subscription:, invoice_subscription:, filtered_fees:, grouped_fees:)
    end
  end
end
