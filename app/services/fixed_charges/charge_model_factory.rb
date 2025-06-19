# frozen_string_literal: true

module FixedCharges
  class ChargeModelFactory
    def self.new_instance(fixed_charge:, aggregation_result:, properties:)
      charge_model = charge_model_class(fixed_charge:)

      charge_model.new(fixed_charge:, aggregation_result:, properties:)
    end

    def self.charge_model_class(fixed_charge:)
      case fixed_charge.charge_model.to_sym
      when :standard
        FixedCharges::ChargeModels::StandardService
      when :graduated
        FixedCharges::ChargeModels::GraduatedService
      else
        raise(NotImplementedError)
      end
    end
  end
end 