# frozen_string_literal: true

module V1
  class TaxSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        rate: model.rate,
        description: model.description,
        applied_to_organization: applied_to_organization?,
        applied_to_billing_entities_codes: model.billing_entities.map(&:code).sort,
        add_ons_count: 0,
        customers_count: 0,
        plans_count: 0,
        charges_count: 0,
        commitments_count: 0,
        created_at: model.created_at.iso8601
      }
    end

    private

    def applied_to_organization?
      return false if default_billing_entity.nil?

      model.billing_entities.any? { |billing_entity| billing_entity.id == default_billing_entity.id }
    end

    def default_billing_entity
      return @default_billing_entity if defined?(@default_billing_entity)

      @default_billing_entity = options[:default_billing_entity] || model.organization.default_billing_entity
    end
  end
end
