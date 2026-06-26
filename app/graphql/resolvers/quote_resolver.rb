# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Resolvers
  class QuoteResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "quotes:view"

    description "Query a quote"

    argument :id, ID, required: true

    type Types::Quotes::Object, null: true

    def resolve(id:)
      current_organization.quotes.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "quote")
    end
  end
end
