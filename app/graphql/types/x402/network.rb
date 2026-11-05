# frozen_string_literal: true

module Types
  module X402
    class Network < Types::BaseObject
      graphql_name "X402Network"

      field :environment, Types::X402::NetworkEnvironmentEnum, null: false
      field :family, Types::X402::NetworkFamilyEnum, null: false
      field :id, ID, null: false
      field :name, String, null: false
    end
  end
end
