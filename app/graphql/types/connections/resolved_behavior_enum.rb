# frozen_string_literal: true

module Types
  module Connections
    class ResolvedBehaviorEnum < Types::BaseEnum
      graphql_name "ConnectionResolvedBehaviorEnum"
      description "How a billing object routes a category: its own choice, or inherited from the customer"

      ConnectionResolvable::ROUTING_BEHAVIORS.each do |behavior|
        value behavior
      end
    end
  end
end
