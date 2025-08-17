# frozen_string_literal: true

class FeeDisplayHelper
  def self.grouped_by_display(fee)
    return "" if !fee.charge? || fee.grouped_by.values.compact.blank?

    " • #{fee.grouped_by.values.compact.join(" • ")}"
  end

  def self.should_display_subscription_fee?(invoice_subscription)
    return false if invoice_subscription.blank?
    return false if invoice_subscription.invoice.progressive_billing?
    return true if invoice_subscription.charge_amount_cents.zero?

    invoice_subscription.subscription_amount_cents.positive?
  end

  def self.format_precise_unit_amount(fee)
    amount = if fee.pricing_unit_usage
      fee.pricing_unit_usage.precise_unit_amount
    else
      fee.precise_unit_amount
    end

    format_with_precision(fee, amount)
  end

  def self.format_with_precision(fee, amount)
    casted_amount = BigDecimal(amount)

    if fee.pricing_unit_usage
      MoneyHelper.format_pricing_unit_with_precision(
        casted_amount,
        fee.pricing_unit_usage.currency
      )
    else
      MoneyHelper.format_with_precision(casted_amount, fee.currency)
    end
  end

  def self.format_as_currency(fee, amount)
    if fee.pricing_unit_usage
      MoneyHelper.format_pricing_unit(
        BigDecimal(amount),
        fee.pricing_unit_usage.currency
      )
    else
      money = amount.to_money(fee.currency)
      MoneyHelper.format(money)
    end
  end

  def self.format_amount(fee)
    if fee.pricing_unit_usage
      MoneyHelper.format_pricing_unit(
        fee.pricing_unit_usage.amount_cents.to_d / 100,
        fee.pricing_unit_usage.currency
      )
    else
      MoneyHelper.format(fee.amount)
    end
  end
end
