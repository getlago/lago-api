# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Invites
    class UpdateInput < Types::BaseInputObject
      graphql_name "UpdateInviteInput"

      argument :id, ID, required: true
      argument :roles, [String], required: false
    end
  end
end
