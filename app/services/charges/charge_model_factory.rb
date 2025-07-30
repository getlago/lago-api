# frozen_string_literal: true

module Charges
  class ChargeModelFactory
    def self.new_instance(charge:, aggregation_result:, properties:, period_ratio: nil)
      charge_model_class = charge_model_class(charge:)
      common_args = {
        charge:,
        aggregation_result:,
        properties:,
        period_ratio:
      }

      # TODO(pricing_group_keys): remove after deprecation of grouped_by
      pricing_group_keys = properties["pricing_group_keys"].presence || properties["grouped_by"]

      if pricing_group_keys.present? && !aggregation_result.aggregations.nil?
        Charges::ChargeModels::GroupedService.new(**common_args.merge(charge_model: charge_model_class))
      else
        charge_model_class.new(**common_args)
      end
    end

    def self.charge_model_class(charge:)
      case charge.charge_model.to_sym
      when :standard
        Charges::ChargeModels::StandardService
      when :graduated
        if charge.prorated?
          Charges::ChargeModels::ProratedGraduatedService
        else
          Charges::ChargeModels::GraduatedService
        end
      when :graduated_percentage
        Charges::ChargeModels::GraduatedPercentageService
      when :package
        Charges::ChargeModels::PackageService
      when :percentage
        Charges::ChargeModels::PercentageService
      when :volume
        Charges::ChargeModels::VolumeService
      when :custom
        Charges::ChargeModels::CustomService
      when :dynamic
        Charges::ChargeModels::DynamicService
      else
        raise NotImplementedError, "Charge model #{charge.charge_model} is not implemented"
      end
    end
  end
end
