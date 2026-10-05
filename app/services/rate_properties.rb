# frozen_string_literal: true

# Catalog tiers only carry their upper bound, as a string: each tier starts where
# the previous one ends, so gaps and overlaps cannot be expressed. Storage keeps
# the shared charge-model shape (numeric from_value / to_value) and billing reads
# it as it reads v1 charges.
module RateProperties
  RANGE_KEYS = %w[graduated_ranges graduated_percentage_ranges volume_ranges].freeze

  # Stored properties as the catalog API shows them.
  def self.present(properties)
    return properties unless properties.is_a?(Hash)

    properties.to_h do |key, value|
      if RANGE_KEYS.include?(key.to_s) && value.is_a?(Array)
        [key, value.map { present_range(it) }]
      else
        [key, value]
      end
    end
  end

  def self.present_range(range)
    range = range.to_h.stringify_keys
    range.except("from_value").merge("to_value" => format_bound(range["to_value"]))
  end

  def self.format_bound(value)
    value.nil? ? nil : BigDecimal(value.to_s).to_s("F").delete_suffix(".0")
  end
end
