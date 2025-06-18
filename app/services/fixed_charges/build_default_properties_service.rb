# frozen_string_literal: true

module FixedCharges
  class BuildDefaultPropertiesService < BaseService
    def initialize(charge_model)
      @charge_model = charge_model
      super
    end

    def call
      case charge_model&.to_sym
      when :standard then default_standard_properties
      when :graduated then default_graduated_properties
      end
    end

    private

    attr_reader :charge_model

    def default_standard_properties
      {amount: "0"}
    end

    def default_graduated_properties
      {
        graduated_ranges: [
          {
            from_value: 0,
            to_value: nil,
            per_unit_amount: "0",
            flat_amount: "0"
          }
        ]
      }
    end
  end
end
