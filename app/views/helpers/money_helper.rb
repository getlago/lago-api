# frozen_string_literal: true

class MoneyHelper
  def self.format(money)
    money&.format(
      format: I18n.t('money.format'),
      decimal_mark: I18n.t('money.decimal_mark'),
      thousands_separator: I18n.t('money.thousands_separator')
    )
  end

  def self.format_with_precision(amount_cents, currency)
    amount_cents = if amount_cents < 1
      BigDecimal("%.6g" % amount_cents)
    else
      amount_cents.round(6)
    end

    Utils::MoneyWithPrecision.from_amount(amount_cents, currency).format(
      format: I18n.t('money.format'),
      decimal_mark: I18n.t('money.decimal_mark'),
      thousands_separator: I18n.t('money.thousands_separator')
    )
  end
end
