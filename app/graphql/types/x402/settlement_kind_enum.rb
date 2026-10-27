# frozen_string_literal: true

module Types
  module X402
    class SettlementKindEnum < Types::BaseEnum
      graphql_name "X402SettlementKindEnum"

      ::X402::Settlement::KINDS.keys.each do |kind|
        value kind
      end
    end
  end
end
