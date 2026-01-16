# frozen_string_literal: true

module Types
  module Memberships
    # @deprecated Use `roles: [String!]` field instead
    class RoleEnum < Types::BaseEnum
      graphql_name "MembershipRole"

      value "admin"
      value "manager"
      value "finance"
    end
  end
end
