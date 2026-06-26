# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Invites
    class CreateInput < Types::BaseInputObject
      graphql_name "CreateInviteInput"

      argument :email, String, required: true
      argument :roles, [String], required: false, default_value: []
    end
  end
end
