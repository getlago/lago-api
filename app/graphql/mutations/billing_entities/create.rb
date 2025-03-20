# frozen_string_literal: true

module Mutations
  module BillingEntities
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "billing_entities:create"

      graphql_name "CreateBillingEntity"
      description "Creates a new Billing Entity"

      input_object_class Types::BillingEntities::CreateInput

      type Types::BillableMetrics::Object

      # We're not allowing now to create a new billing entity
      def resolve(_args)
        current_organization.default_billing_entity
      end
    end
  end
end
