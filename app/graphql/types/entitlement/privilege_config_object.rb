# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Entitlement
    class PrivilegeConfigObject < Types::BaseObject
      description "Configuration object for privileges"

      field :select_options, [String], null: true, description: "Available options for select type privileges"
    end
  end
end
