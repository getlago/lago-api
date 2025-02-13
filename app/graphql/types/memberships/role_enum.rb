# frozen_string_literal: true

module Types
  module Memberships
    class RoleEnum < Types::BaseEnum
      graphql_name "MembershipRole"

      Membership::ROLES.keys.each do |role|
        value role
      end
    end
  end
end
