# frozen_string_literal: true

module Charges
  class ChargeModelFactory
    def self.new_instance(charge:, aggregation_result:, properties:)
      charge_model_class(charge:, aggregation_result:).new(charge:, aggregation_result:, properties:)
    end

    def self.charge_model_class(charge:, aggregation_result:)
      case charge.charge_model.to_sym
      when :standard
        if charge.properties["grouped_by"].present? && !aggregation_result.aggregations.nil?
          Charges::ChargeModels::GroupedStandardService
        else
          Charges::ChargeModels::StandardService
        end
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
      else
        raise(NotImplementedError)
      end
    end
  end
end
