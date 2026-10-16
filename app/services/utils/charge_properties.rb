# frozen_string_literal: true

module Utils
  class ChargeProperties
    # Charge properties are read in snake_case by the charge models and their validators, while the
    # payloads carrying them are written in the camelCase of the GraphQL schema they were read from:
    # a quote's billing_items is a free-form JSON scalar, so nothing converts it on the way in.
    # Underscoring is idempotent, so a payload already written in snake_case normalizes to itself and
    # both spellings are accepted.
    PRESERVED_KEY = "custom_properties"

    # Anything that is not an object is returned as it arrived, for the callers to reject the way
    # they already do.
    def self.underscore_keys(properties)
      return properties unless properties.is_a?(Hash)

      properties.to_h do |key, value|
        normalized_key = key.to_s.underscore

        # custom_properties carries the keys the customer defined for their own aggregation, so
        # renaming them would change what that aggregation reads at billing time.
        if normalized_key == PRESERVED_KEY
          [normalized_key, value]
        else
          [normalized_key, underscore_value(value)]
        end
      end
    end

    def self.underscore_value(value)
      case value
      when Hash then underscore_keys(value)
      when Array then value.map { underscore_value(it) }
      else value
      end
    end
    private_class_method :underscore_value
  end
end
