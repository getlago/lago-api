# frozen_string_literal: true

module Types
  module Connections
    class ChoiceInput < Types::BaseInputObject
      graphql_name "ConnectionChoiceInput"
      description "Route a billing object to a specific customer connection, or skip the category"

      argument :behavior, Types::Connections::BehaviorEnum, required: false
      argument :code, String, required: false
    end
  end
end
