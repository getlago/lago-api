# frozen_string_literal: true

module Types
  # This type is used to expose organization information to users that
  # are potentially not members of that organization. It's used where the organization
  # is a relationship on the other object.
  # It cannot expose any sensitive fields like `api_key` because there is a risk of GraphQL traversal attack.
  #
  # Only the `CurrentOrganizationType` can expose sensitive fields.
  #
  # Ex: current organization > memberships > another member > organizations can lead to an organization
  #     the current user is not supposed to have access to
  class OrganizationType < Types::BaseObject
    description 'Safe Organization Type'

    field :id, ID, null: false

    field :default_currency, Types::CurrencyEnum, null: false
    field :logo_url, String
    field :name, String, null: false
    field :timezone, Types::TimezoneEnum, null: true

    field :billing_configuration, Types::Organizations::BillingConfiguration, null: true
  end
end
