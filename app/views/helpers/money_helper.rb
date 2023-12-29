# frozen_string_literal: true

class MoneyHelper
  def self.format(money)
    money&.format(
      format: I18n.t('money.format'),
      decimal_mark: I18n.t('money.decimal_mark'),
      thousands_separator: I18n.t('money.thousands_separator'),
    )
  end

  def self.format_with_precision(amount_cents, currency)
    Money.default_infinite_precision = true
    Money.from_amount(amount_cents, currency).format(
      format: I18n.t('money.format'),
      decimal_mark: I18n.t('money.decimal_mark'),
      thousands_separator: I18n.t('money.thousands_separator'),
    )
    Money.default_infinite_precision = false
  end
end
