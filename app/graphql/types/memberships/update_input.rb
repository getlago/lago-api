# frozen_string_literal: true

module Types
  module Memberships
    class UpdateInput < Types::BaseInputObject
      graphql_name "UpdateMembershipInput"

      argument :id, ID, required: true
      argument :roles, [String], required: false
    end
  end
end
