# frozen_string_literal: true

module Types
  module Superset
    module Dashboard
      class Object < Types::BaseObject
        graphql_name "SupersetDashboard"

        field :id, String, null: false
        field :dashboard_title, String, null: false
        field :embedded_id, String, null: false
        field :guest_token, String, null: false
      end
    end
  end
end
