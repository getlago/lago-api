# frozen_string_literal: true

module Resolvers
  class RolesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "roles:view"

    description "Query roles available for the organization"

    type [Types::RoleType], null: false

    def resolve
      Role
        .where(organization_id: [nil, current_organization.id])
        .order(Role.arel_table[:organization_id].asc.nulls_first)
        .order(Arel::Nodes::NamedFunction.new("LOWER", [Role.arel_table[:name]]).asc)
    end
  end
end
