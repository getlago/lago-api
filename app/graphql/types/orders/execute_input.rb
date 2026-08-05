# frozen_string_literal: true

module Types
  module Orders
    class ExecuteInput < Types::BaseInputObject
      description "Execute Order input arguments"

      argument :id, ID, required: true
    end
  end
end
