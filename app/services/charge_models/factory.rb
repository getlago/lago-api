# frozen_string_literal: true

module ChargeModels
  class Factory
    def self.new_instance(pricing_structure:, aggregation_result:, period_ratio: 1.0, calculate_projected_usage: false)
      unless pricing_structure.is_a?(ChargeModels::PricingStructure)
        raise NotImplementedError, "Pricing structure: #{pricing_structure.class.name} is not implemented"
      end

      charge_model_class = charge_model_class(
        pricing_structure:,
        has_aggregator: aggregation_result.respond_to?(:aggregator) && !aggregation_result.aggregator.nil?
      )

      common_args = {
        pricing_structure:,
        aggregation_result:,
        period_ratio:,
        calculate_projected_usage:
      }

      # TODO(pricing_group_keys): remove after deprecation of grouped_by
      pricing_group_keys = pricing_structure.properties["pricing_group_keys"].presence || pricing_structure.properties["grouped_by"]
      use_grouped_service = pricing_group_keys.present? || pricing_structure.accepts_target_wallet

      if use_grouped_service && !aggregation_result.aggregations.nil?
        ChargeModels::GroupedService.new(**common_args.merge(charge_model: charge_model_class))
      else
        charge_model_class.new(**common_args)
      end
    end

    # The has_aggregator param determines whether to use prorated charge models.
    # When forecasting (no aggregator available), prorated graduated charges fall back to
    # the non-prorated GraduatedService since per-event aggregation data is not available.
    # This allows forecasting to work for all charge types without failing on nil aggregator.
    def self.charge_model_class(pricing_structure:, has_aggregator: true)
      case pricing_structure.charge_model.to_sym
      when :standard
        ChargeModels::StandardService
      when :graduated
        if pricing_structure.prorated && has_aggregator
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
        raise NotImplementedError, "Charge model #{pricing_structure.charge_model} is not implemented"
      end
    end

    def self.in_advance_charge_model_class(pricing_structure:)
      case pricing_structure.charge_model.to_sym
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
        raise NotImplementedError, "Charge model #{pricing_structure.charge_model} is not implemented"
      end
    end
  end
end
