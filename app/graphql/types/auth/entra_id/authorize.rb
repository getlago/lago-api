# frozen_string_literal: true

module Types
  module Auth
    module EntraId
      class Authorize < Types::BaseObject
        # NOTE: Types::Auth::Okta::Authorize already owns the default
        #       "Authorize" type name, so this one must be explicit.
        graphql_name "EntraIdAuthorize"

        field :url, String, null: false
      end
    end
  end
end
