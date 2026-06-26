# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Utils
  class MoneyWithPrecision < Money
    self.default_infinite_precision = true
  end
end
