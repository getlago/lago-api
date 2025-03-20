# frozen_string_literal: true

module Mutations
  module BillingEntities
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "billing_entities:update"

      graphql_name "UpdateBillingEntity"
      description "Updates a new Billing Entity"

      input_object_class Types::BillingEntities::UpdateInput

      type Types::BillableMetrics::Object

      # We're not allowing now to update billing entities
      def resolve(_args)
        current_organization.default_billing_entity
      end
    end
  end
end
