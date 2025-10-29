# frozen_string_literal: true

module ChargeModels
  class Factory
    def self.new_instance(chargeable:, aggregation_result:, properties:, period_ratio: 1.0, calculate_projected_usage: false)
      raise NotImplementedError, "Chargeable: #{chargeable.class.name} is not implemented" unless chargeable.is_a?(Charge) || chargeable.is_a?(FixedCharge)

      charge_model_class = charge_model_class(chargeable:)
      common_args = {
        charge: chargeable,
        aggregation_result:,
        properties:,
        period_ratio:,
        calculate_projected_usage:
      }

      # TODO(pricing_group_keys): remove after deprecation of grouped_by
      pricing_group_keys = properties["pricing_group_keys"].presence || properties["grouped_by"]

      if pricing_group_keys.present? && !aggregation_result.aggregations.nil?
        ChargeModels::GroupedService.new(**common_args.merge(charge_model: charge_model_class))
      else
        charge_model_class.new(**common_args)
      end
    end

    def self.charge_model_class(chargeable:)
      case chargeable.charge_model.to_sym
      when :standard
        ChargeModels::StandardService
      when :graduated
        if chargeable.prorated?
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
        raise NotImplementedError, "Charge model #{chargeable.charge_model} is not implemented"
      end
    end

    def self.in_advance_charge_model_class(chargeable:)
      case chargeable.charge_model.to_sym
      when :standard
        ChargeModels::StandardService
      when :graduated
        ChargeModels::GraduatedService
      when :graduated_percentage
        ChargeModels::GraduatedPercentageService
      when :package
        ChargeModels::PackageService
      when :percentage
        ChargeModels::PercentageService
      when :custom
        ChargeModels::CustomService
      when :dynamic
        ChargeModels::DynamicService
      else
        raise NotImplementedError, "Charge model #{chargeable.charge_model} is not implemented"
      end
    end
  end
end
