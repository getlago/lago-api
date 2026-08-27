# frozen_string_literal: true

module Fees
  class ChargeService
    CONTEXTS = [nil, :current_usage, :invoice_preview, :recurring, :finalize].freeze
    # NOTE: Accepted for callers that still use invoice-level contexts with charge fee calculation.
    DEPRECATED_CONTEXTS = [:refresh, :draft].freeze

    Options = Data.define(
      :context,
      :apply_taxes,
      :calculate_projected_usage,
      :with_zero_units_filters,
      :usage_filters,
      :skip_adjusted_fees
    ) do
      def self.default
        new
      end

      def initialize(
        context: nil,
        apply_taxes: false,
        calculate_projected_usage: false,
        with_zero_units_filters: true,
        usage_filters: UsageFilters::NONE,
        skip_adjusted_fees: false
      )
        validate_context!(context)
        validate_usage_filters!(usage_filters)
        validate_boolean!(:apply_taxes, apply_taxes)
        validate_boolean!(:calculate_projected_usage, calculate_projected_usage)
        validate_boolean!(:with_zero_units_filters, with_zero_units_filters)
        validate_boolean!(:skip_adjusted_fees, skip_adjusted_fees)

        super
      end

      def current_usage?
        context == :current_usage
      end

      def invoice_preview?
        context == :invoice_preview
      end

      def recurring?
        context == :recurring
      end

      def finalize?
        context == :finalize
      end

      private

      def validate_context!(context)
        accepted_contexts = CONTEXTS + DEPRECATED_CONTEXTS
        return if accepted_contexts.include?(context)

        raise ArgumentError, "context '#{context}' must be one of: #{accepted_contexts.compact.join(", ")}"
      end

      def validate_usage_filters!(usage_filters)
        return if usage_filters.is_a?(UsageFilters)

        raise ArgumentError, "usage_filters must be a UsageFilters"
      end

      def validate_boolean!(name, value)
        return if value == true || value == false

        raise ArgumentError, "#{name} must be a boolean"
      end
    end
  end
end
