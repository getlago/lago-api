# frozen_string_literal: true

module Types
  module X402
    class SettlementStatusEnum < Types::BaseEnum
      graphql_name "X402SettlementStatusEnum"

      ::X402::Settlement::STATUSES.keys.each do |status|
        value status
      end
    end
  end
end
