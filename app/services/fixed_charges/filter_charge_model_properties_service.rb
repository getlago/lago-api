# frozen_string_literal: true

module FixedCharges
  class FilterChargeModelPropertiesService < BaseService
    def initialize(fixed_charge:, properties:)
      @fixed_charge = fixed_charge
      @properties = properties&.with_indifferent_access || {}

      super
    end

    def call
      result.properties = slice_properties || {}

      result
    end

    private

    attr_reader :fixed_charge, :properties

    delegate :charge_model, to: :fixed_charge

    def slice_properties
      attributes = []
      attributes += charge_model_attributes || []

      properties.slice(*attributes)
    end

    def charge_model_attributes
      case charge_model&.to_sym
      when :standard
        %i[amount]
      when :graduated
        %i[graduated_ranges]
      end
    end
  end
end
