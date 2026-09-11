# frozen_string_literal: true

module Types
  module UsageAttributionTypes
    class RoleEnum < Types::BaseEnum
      graphql_name "UsageAttributionTypeRoleEnum"

      UsageAttributionType::ROLES.keys.each do |role|
        value role
      end
    end
  end
end
