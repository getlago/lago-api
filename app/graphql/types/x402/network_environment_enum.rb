# frozen_string_literal: true

module Types
  module X402
    class NetworkEnvironmentEnum < Types::BaseEnum
      graphql_name "X402NetworkEnvironmentEnum"

      ::X402::Network::NETWORKS.values.uniq.each do |environment|
        value environment
      end
    end
  end
end
