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
        add_ons_count: 0,
        customers_count: 0,
        plans_count: 0,
        charges_count: 0,
        commitments_count: 0,
        created_at: model.created_at.iso8601
      }
    end

    private

    # A tax is considered applied to the organization when it is applied to the
    # organization's default billing entity. The legacy `applied_to_organization`
    # column is deprecated and is not kept in sync when taxes are managed directly
    # on a billing entity.
    def applied_to_organization?
      return false if default_billing_entity_id.nil?

      model.billing_entities_taxes.any? do |applied_tax|
        applied_tax.billing_entity_id == default_billing_entity_id
      end
    end

    def default_billing_entity_id
      return @default_billing_entity_id if defined?(@default_billing_entity_id)

      @default_billing_entity_id =
        options[:default_billing_entity_id] || model.organization.default_billing_entity&.id
    end
  end
end
