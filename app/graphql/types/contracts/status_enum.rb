# frozen_string_literal: true

module Types
  module Contracts
    class StatusEnum < Types::BaseEnum
      graphql_name "ContractStatusEnum"

      Contract::STATUSES.each_key do |type|
        value type
      end
    end
  end
end
