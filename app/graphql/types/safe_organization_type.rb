# frozen_string_literal: true

module Types
  # This type is used to expose organization information to users that
  # are potentially not members of that organization.
  #
  # It has to be used in place of OrganizationType where there is a risk
  # of GraphQL traversal attack.
  # Ex: current organization > memberships > another member > organizations can lead to an organization
  #     the current user is not supposed to have access to
  class SafeOrganizationType < Types::BaseObject
    description 'Safe Organization Type'

    field :id, ID, null: false
    field :logo_url, String
    field :name, String, null: false, permission: 'non_existing_permission'
    field :timezone, Types::TimezoneEnum, null: true
  end
end
