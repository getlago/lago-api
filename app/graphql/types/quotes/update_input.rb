# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Quotes
    class UpdateInput < BaseInputObject
      graphql_name "UpdateQuoteInput"

      argument :id, ID, required: true
      argument :owners, [ID], required: false
    end
  end
end
