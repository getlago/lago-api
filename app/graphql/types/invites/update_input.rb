# frozen_string_literal: true

module Types
  module Invites
    class UpdateInput < Types::BaseInputObject
      graphql_name "UpdateInviteInput"

      argument :id, ID, required: true
      argument :role, Types::Memberships::RoleEnum, required: false, deprecation_reason: "Use `roles` instead"
      argument :roles, [String], required: false
    end
  end
end
