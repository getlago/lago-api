# frozen_string_literal: true

class RoundingHelper
  def self.round_decimal_part(num, decimal_sig_figs = 6)
    return BigDecimal("%.#{decimal_sig_figs}g" % num).to_s if num.abs < 1

    rounded_decimal_part = BigDecimal(num.to_s).frac.round(decimal_sig_figs)
    rounded_number = num.round(decimal_sig_figs)

    rounded_decimal_part.zero? ? rounded_number.to_i.to_s : rounded_number.to_s
  end
end
