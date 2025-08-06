# frozen_string_literal: true

module ChargeModels
  class FilterPropertiesService < BaseService
    def initialize(chargeable:, properties:)
      @chargeable = chargeable
      @properties = properties&.with_indifferent_access || {}

      super
    end

    def call
      result.properties = filter_service.call.properties
      result
    end

    private

    attr_reader :chargeable, :properties

    def filter_service
      case chargeable
      when Charge
        ChargeModels::FilterProperties::ChargeService.new(chargeable:, properties:)
      when FixedCharge
        ChargeModels::FilterProperties::FixedChargeService.new(chargeable:, properties:)
      else
        raise ArgumentError, "Unsupported chargeable type: #{chargeable.class}"
      end
    end
  end
end
