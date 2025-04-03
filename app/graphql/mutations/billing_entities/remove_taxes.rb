# frozen_string_literal: true

module Mutations
  module BillingEntities
    class RemoveTaxes < ::Mutations::BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization
      graphql_name "RemoveTaxes"

      argument :billing_entity_id, ID, required: true
      argument :tax_codes, [String], required: true

      field :applied_taxes, [Types::Taxes::Object], null: false

      def resolve(billing_entity_id:, tax_codes:)
        billing_entity = current_organization.billing_entities.find(billing_entity_id)
        taxes_to_delete = billing_entity.taxes.where(code: tax_codes)
        billing_entity.applied_taxes.where(tax_id: taxes_to_delete.ids).destroy_all
        billing_entity.taxes.reload
      end
    end
  end
end
