# frozen_string_literal: true

module V1
  class TaxWithBillingEntitiesSerializer < TaxSerializer
    def serialize
      super.merge(
        applied_to_organization: applied_to_organization?,
        applied_to_billing_entities_codes: model.billing_entities.map(&:code).sort
      )
    end

    private

    def applied_to_organization?
      default_billing_entity = options[:default_billing_entity]
      if default_billing_entity.nil?
        false
      else
        model.billing_entities.any? { |billing_entity| billing_entity.id == default_billing_entity.id }
      end
    end
  end
end
