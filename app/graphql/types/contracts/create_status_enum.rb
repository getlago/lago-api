# frozen_string_literal: true

module Types
  module Contracts
    # Only a draft is chosen at creation: the start date decides between pending and active.
    class CreateStatusEnum < Types::BaseEnum
      graphql_name "CreateContractStatusEnum"

      value "draft"
    end
  end
end
