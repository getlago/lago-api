# frozen_string_literal: true

class MoneyHelper
  def self.format(money)
    money&.format(
      format: I18n.t('money.format'),
      decimal_mark: I18n.t('money.decimal_mark'),
      thousands_separator: I18n.t('money.thousands_separator'),
    )
  end
end
