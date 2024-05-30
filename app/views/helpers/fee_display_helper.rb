# frozen_string_literal: true

class FeeDisplayHelper
  def self.grouped_by_display(fee)
    return '' unless fee.charge?
    return '' if fee.charge.properties['grouped_by'].blank?
    return '' if fee.grouped_by.values.compact.blank?

    " • #{fee.grouped_by.values.compact.join(" • ")}"
  end

  def self.should_display_subscription_fee?(invoice_subscription)
    return false if invoice_subscription.blank?
    return true if invoice_subscription.charge_amount_cents.zero?

    invoice_subscription.subscription_amount_cents.positive?
  end
end
