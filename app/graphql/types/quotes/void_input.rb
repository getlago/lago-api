# frozen_string_literal: true

module Types
  module Quotes
    class VoidInput < Types::BaseInputObject
      graphql_name "VoidQuoteInput"

      argument :id, ID, required: true
      argument :reason, Types::Quotes::VoidReasonEnum, required: true
    end
  end
end
