# frozen_string_literal: true

module Types
  module Organizations
    class CustomerPortalFieldEnum < Types::BaseEnum
      description "Customer fields that can be sent from the customer portal"

      Organization::CUSTOMER_PORTAL_FIELDS.each do |value|
        value(value)
      end
    end
  end
end
