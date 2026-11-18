# frozen_string_literal: true

module Types
  module Organizations
    class ActivationStatusEnum < Types::BaseEnum
      graphql_name "OrganizationActivationStatusEnum"
      description "Whether an organization is open, or a self-serve production organization waiting for a payment method"

      value "pending_payment_method", description: "Waiting for a payment method before it opens"
      value "active", description: "Open"
    end
  end
end
