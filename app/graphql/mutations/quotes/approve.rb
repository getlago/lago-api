# frozen_string_literal: true

module Mutations
  module Quotes
    class Approve < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "quotes:approve"

      graphql_name "ApproveQuote"
      description "Approve a quote"

      argument :id, ID, required: true

      type Types::Quotes::Object

      def resolve(**args)
        quote = current_organization.quotes.find_by(id: args[:id])
        result = ::Quotes::ApproveService.call(quote: quote)

        result.success? ? result.quote : result_error(result)
      end
    end
  end
end
