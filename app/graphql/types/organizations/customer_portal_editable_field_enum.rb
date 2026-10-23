# frozen_string_literal: true

module Types
  module Organizations
    class CustomerPortalEditableFieldEnum < Types::BaseEnum
      description "Customer fields that can be edited from the customer portal"

      Organization::CUSTOMER_PORTAL_EDITABLE_FIELDS.each do |value|
        value(value)
      end
    end
  end
end
