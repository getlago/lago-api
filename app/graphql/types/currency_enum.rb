# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  class CurrencyEnum < Types::BaseEnum
    Currencies::ACCEPTED_CURRENCIES.each do |code, description|
      value code, description
    end
  end
end
