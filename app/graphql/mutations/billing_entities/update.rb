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

      type Types::BillingEntities::Object

      # We're not allowing now to update billing entities
      def resolve(args)
        billing_entity = current_organization.billing_entities.find_by(code: args[:code])
        result = ::BillingEntities::UpdateService.call(billing_entity: billing_entity, params: args)
        result.success? ? result.billing_entity : result_error(result)
      end
    end
  end
end
