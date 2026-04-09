# frozen_string_literal: true

module Mutations
  module Quotes
    class Void < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "quotes:void"

      graphql_name "VoidQuote"
      description "Void a quote"

      argument :id, ID, required: true
      argument :reason, Types::Quotes::VoidReasonEnum, required: true

      type Types::Quotes::Object

      def resolve(**args)
        quote = current_organization.quotes.find_by(id: args[:id])
        result = ::Quotes::VoidService.call(quote: quote, reason: args[:reason])

        result.success? ? result.quote : result_error(result)
      end
    end
  end
end
