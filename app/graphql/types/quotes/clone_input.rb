# frozen_string_literal: true

module Types
  module Quotes
    class CloneInput < Types::BaseInputObject
      graphql_name "CloneQuoteInput"

      argument :id, ID, required: true
    end
  end
end
