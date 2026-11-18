# frozen_string_literal: true

module Types
  module Organizations
    # The other organization of a production and sandbox pair. It carries no link fields, so it cannot be traversed.
    class LinkedOrganizationType < Types::BaseObject
      description "Production organization of a sandbox, or sandbox of a production organization"

      field :id, ID, null: false
      field :name, String, null: false
      field :slug, String, null: false
    end
  end
end
