# frozen_string_literal: true

module Types
  module X402
    class NetworkFamilyEnum < Types::BaseEnum
      graphql_name "X402NetworkFamilyEnum"

      ::X402::Network::FAMILIES.values.each do |family|
        value family
      end
    end
  end
end
