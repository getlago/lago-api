# frozen_string_literal: true

module Types
  module Organizations
    class ActivationStatusEnum < Types::BaseEnum
      graphql_name "OrganizationActivationStatusEnum"
      description "Whether an organization is open, or a self-serve production organization waiting for a payment method"

      DESCRIPTIONS = {
        pending_payment_method: "Waiting for a payment method before it opens",
        active: "Open"
      }.freeze

      Organization::ACTIVATION_STATUSES.each do |key, status|
        value status, description: DESCRIPTIONS.fetch(key)
      end
    end
  end
end
