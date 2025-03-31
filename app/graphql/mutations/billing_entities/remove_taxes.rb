# frozen_string_literal: true

module Mutations
  module BillingEntities
    class RemoveTaxes < ::Mutations::BaseMutation
      graphql_name "RemoveTaxes"

      argument :billing_entity_id, ID, required: true
      argument :tax_codes, [String], required: true

      def resolve(billing_entity_id:, tax_codes:)
        billing_entity = current_organization.billing_entities.find(billing_entity_id)
        billing_entity.applied_taxes.where(tax: { code: tax_codes }).destroy_all
      end
    end
  end
end
