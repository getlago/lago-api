# frozen_string_literal: true

module UsageAttributions
  # Resolves the account tree labels of an event: for each usage attribution type, the value of
  # the first of its attribution keys found in the properties, keyed by the type code.
  #
  # Mirrors `BuildAttributionLabels` in the events-processor, which stamps the same labels on the
  # enriched events: both must resolve the same values, or the attribution values stored here
  # would not match the labels the account tree reads from ClickHouse.
  class LabelsService < BaseService
    MAX_VALUE_LENGTH = 255

    Result = BaseResult[:labels]

    def initialize(attribution_types:, properties:)
      @attribution_types = attribution_types
      @properties = properties || {}

      super
    end

    def call
      result.labels = attribution_types.each_with_object({}) do |attribution_type, labels|
        value = attribution_type.attribution_keys.lazy.filter_map { label_value(properties[it]) }.first

        if value
          labels[attribution_type.code] = value
        end
      end

      result
    end

    private

    attr_reader :attribution_types, :properties

    def label_value(property)
      value = case property
      when nil, Hash, Array then return
      when Float then format_float(property)
      else property.to_s
      end

      if value.empty? || value.length > MAX_VALUE_LENGTH
        nil
      else
        value
      end
    end

    def format_float(value)
      BigDecimal(value.to_s).to_s("F").delete_suffix(".0")
    end
  end
end
