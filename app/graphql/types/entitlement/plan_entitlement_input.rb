# frozen_string_literal: true

module Types
  module Entitlement
    class PlanEntitlementInput < Types::BaseInputObject
      description "Input for updating a plan entitlement"

      argument :feature_code, String, required: true
      argument :privileges, [PlanEntitlementPrivilegeInput], required: false, description: "The privileges configuration"
    end
  end
end
