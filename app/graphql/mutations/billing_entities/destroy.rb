# frozen_string_literal: true

module Mutations
  module BillingEntities
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "billing_entities:destroy"

      graphql_name "DestroyBillingEntity"
      description "Destroys a new Billing Entity"

      argument :code, String, required: true
      field :code, String, null: true

      # We're not allowing now to destroy billing entities
      def resolve(_code:)
        current_organization.default_billing_entity
      end
    end
  end
end
