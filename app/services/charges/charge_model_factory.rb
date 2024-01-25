# frozen_string_literal: true

module Charges
  class ChargeModelFactory
    def self.new_instance(charge:, aggregation_result:, properties:)
      charge_model_class(charge:).new(charge:, aggregation_result:, properties:)
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
      else
        raise(NotImplementedError)
      end
    end
  end
end
