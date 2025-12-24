# frozen_string_literal: true

module Types
  module Invites
    class CreateInput < Types::BaseInputObject
      graphql_name "CreateInviteInput"

      argument :email, String, required: true
      argument :role, Types::Memberships::RoleEnum, required: false, deprecation_reason: "Use roles argument instead"
      argument :roles, [String], required: false, default_value: []
    end
  end
end
