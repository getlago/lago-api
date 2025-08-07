# frozen_string_literal: true

module Charges
  class ChargeModelFactory
    def self.new_instance(charge:, aggregation_result:, properties:)
      charge_model = charge_model_class(charge:)

      # TODO(pricing_group_keys): remove after deprecation of grouped_by
      pricing_group_keys = properties["pricing_group_keys"].presence || properties["grouped_by"]

      if pricing_group_keys.present? && !aggregation_result.aggregations.nil?
        Charges::ChargeModels::GroupedService.new(charge_model: charge_model, charge:, aggregation_result:, properties:)
      else
        charge_model.new(charge:, aggregation_result:, properties:)
      end
    end

    def self.charge_model_class(charge:)
      case charge.charge_model.to_sym
      when :standard
        ChargeModels::StandardService
      when :graduated
        if charge.prorated?
          ChargeModels::ProratedGraduatedService
        else
          ChargeModels::GraduatedService
        end
      when :graduated_percentage
        ChargeModels::GraduatedPercentageService
      when :package
        ChargeModels::PackageService
      when :percentage
        ChargeModels::PercentageService
      when :volume
        ChargeModels::VolumeService
      when :custom
        ChargeModels::CustomService
      when :dynamic
        ChargeModels::DynamicService
      else
        raise(NotImplementedError)
      end
    end
  end
end
