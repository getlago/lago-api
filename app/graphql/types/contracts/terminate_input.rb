# frozen_string_literal: true

module Types
  module Contracts
    class TerminateInput < BaseInputObject
      graphql_name "TerminateContractInput"
      description "Terminate contract input arguments"

      argument :id, ID, required: true
    end
  end
end
