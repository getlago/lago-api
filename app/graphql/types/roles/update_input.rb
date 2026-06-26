# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Roles
    class UpdateInput < BaseInputObject
      description "Update Role input arguments"

      argument :description, String, required: false
      argument :id, ID, required: true
      argument :name, String, required: false
      argument :permissions, [Types::PermissionEnum], required: false
    end
  end
end
