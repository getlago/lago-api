# frozen_string_literal: true

module Types
  module Auth
    module Google
      class AuthUrl < Types::BaseObject
        field :state_secret, String, null: true, description: "Kept by the tab that starts the flow and sent back with the code. Set when self-serve is enabled"
        field :url, String, null: false
      end
    end
  end
end
