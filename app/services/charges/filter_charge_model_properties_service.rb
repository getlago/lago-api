# frozen_string_literal: true

module Charges
  class FilterChargeModelPropertiesService < BaseService
    def initialize(charge:, properties:)
      @charge = charge
      @properties = properties&.with_indifferent_access || {}

      super
    end

    def call
      result.properties = slice_properties || {}
      result
    end

    private

    attr_reader :charge, :properties

    delegate :charge_model, to: :charge

    def slice_properties
      attributes = []
      attributes << :custom_properties if charge.billable_metric.custom_agg?
      attributes += charge_model_attributes || []

      sliced_attributes = properties.slice(*attributes)
      sliced_attributes[:grouped_by].reject!(&:empty?) if charge.supports_grouped_by? && sliced_attributes[:grouped_by].present?
      sliced_attributes
    end

    def charge_model_attributes
      case charge_model&.to_sym
      when :standard
        attributes = %i[amount]
        attributes << :grouped_by if properties[:grouped_by].present?

        attributes
      when :graduated
        %i[graduated_ranges]
      when :graduated_percentage
        %i[graduated_percentage_ranges]
      when :package
        %i[amount free_units package_size]
      when :percentage
        %i[
          fixed_amount
          free_units_per_events
          free_units_per_total_aggregation
          per_transaction_max_amount
          per_transaction_min_amount
          rate
        ]
      when :volume
        %i[volume_ranges]
      when :dynamic
        if properties[:grouped_by].present?
          [:grouped_by]
        end
      end
    end
  end
end
