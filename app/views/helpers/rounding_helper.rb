# frozen_string_literal: true

class RoundingHelper
  def self.round_decimal_part(num, decimal_sig_figs = 6)
    bd = BigDecimal(num.to_s)

    int_part = bd.floor  # Extract integer part
    decimal_part = bd - int_part  # Get only the decimal part

    if decimal_part.zero?
      return int_part.to_s  # If there's no decimal part, return integer as a string
    end

    # Count leading zeros after decimal to adjust precision
    leading_zeros = decimal_part.to_s("F")[2..].index(/[^0]/) || 0
    precision = int_part.zero? ? leading_zeros + decimal_sig_figs : decimal_sig_figs

    # Round the decimal part
    rounded_decimal = decimal_part.round(precision)

    # Combine integer and rounded decimal part
    result = int_part + rounded_decimal
    result.to_s("F")  # Convert to string to maintain formatting
  end
end
