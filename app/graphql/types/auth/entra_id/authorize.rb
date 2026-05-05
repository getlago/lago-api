# frozen_string_literal: true

module Types
  module Auth
    module EntraId
      class Authorize < Types::BaseObject
        field :url, String, null: false
      end
    end
  end
end
