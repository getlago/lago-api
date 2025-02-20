# frozen_string_literal: true

class MoneyHelper
  SYMBOLS_CURRENCIES = %w[$ € £ ¥].freeze

  def self.format(money)
    money&.format(
      format: currency_format(money&.currency),
      decimal_mark: I18n.t("money.decimal_mark"),
      thousands_separator: I18n.t("money.thousands_separator")
    )
  end

  def self.format_with_precision(amount_cents, currency)
    amount_cents = if amount_cents < 1
      BigDecimal("%.6g" % amount_cents)
    else
      amount_cents.round(6)
    end

    money = Utils::MoneyWithPrecision.from_amount(amount_cents, currency)
    money.format(
      format: currency_format(money.currency),
      decimal_mark: I18n.t("money.decimal_mark"),
      thousands_separator: I18n.t("money.thousands_separator")
    )
  end

  def self.currency_format(money_currency)
    if SYMBOLS_CURRENCIES.include?(money_currency&.symbol)
      I18n.t("money.format")
    else
      I18n.t("money.custom_format", iso_code: money_currency&.iso_code)
    end
  end
end
