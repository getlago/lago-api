# frozen_string_literal: true

module Types
  module Contracts
    class PublishInput < BaseInputObject
      graphql_name "PublishContractInput"
      description "Publish contract input arguments"

      argument :id, ID, required: true
    end
  end
end
