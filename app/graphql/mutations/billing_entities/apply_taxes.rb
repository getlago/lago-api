# frozen_string_literal: true

module Mutations
  module BillingEntities
    class ApplyTaxes < ::Mutations::BaseMutation
      graphql_name "ApplyTaxes"

      argument :billing_entity_id, ID, required: true
      argument :tax_codes, [String], required: true

      field :applied_taxes, [Types::Taxes::Object], null: false

      # todo: change it to use service
      def resolve(billing_entity_id:, tax_codes:)
        billing_entity = current_organization.billing_entities.find(billing_entity_id)
        tax_codes.each do |tax_code|
          tax = current_organization.taxes.find_by(code: tax_code)
          billing_entity.applied_taxes.create(tax:)
        end

        billing_entity.applied_taxes
      end
    end
  end
end
