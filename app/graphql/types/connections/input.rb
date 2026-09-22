# frozen_string_literal: true

module Types
  module Connections
    class Input < Types::BaseInputObject
      graphql_name "ConnectionsInput"
      description "Per-object connection routing, one choice per category. An omitted category keeps whatever is stored"

      BillingObjectConnection::CATEGORIES.each_key do |category|
        argument category, Types::Connections::ChoiceInput, required: false
      end
    end
  end
end
