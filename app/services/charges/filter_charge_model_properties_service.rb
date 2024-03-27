# frozen_string_literal: true

module Charges
  class FilterChargeModelPropertiesService < BaseService
    def initialize(charge_model:, properties:)
      @charge_model = charge_model
      @properties = properties&.with_indifferent_access || {}

      super
    end

    def call
      result.properties = slice_properties || {}
      result
    end

    private

    attr_reader :charge_model, :properties

    def slice_properties
      case charge_model&.to_sym
      when :standard
        properties.slice(:amount, :grouped_by).tap do |p|
          next if p[:grouped_by].blank?

          p[:grouped_by].reject!(&:empty?)
        end
      when :graduated
        properties.slice(:graduated_ranges)
      when :graduated_percentage
        properties.slice(:graduated_percentage_ranges)
      when :package
        properties.slice(:amount, :free_units, :package_size)
      when :percentage
        properties.slice(
          :fixed_amount,
          :free_units_per_events,
          :free_units_per_total_aggregation,
          :per_transaction_max_amount,
          :per_transaction_min_amount,
          :rate
        )
      when :volume
        properties.slice(:volume_ranges)
      end
    end
  end
end
