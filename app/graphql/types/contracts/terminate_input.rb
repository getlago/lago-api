# frozen_string_literal: true

module Types
  module Contracts
    class TerminateInput < BaseInputObject
      graphql_name "TerminateContractInput"
      description "Terminate contract input arguments"

      argument :external_id, String, required: true, description: "External id of the contract to terminate"
    end
  end
end
