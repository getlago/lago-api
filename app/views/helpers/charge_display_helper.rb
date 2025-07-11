# frozen_string_literal: true

class ChargeDisplayHelper
  def self.format_min_amount(charge)
    money = Money.from_cents(charge.min_amount_cents, charge.plan.amount.currency)
    MoneyHelper.format(money)
  end
end
