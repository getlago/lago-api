# frozen_string_literal: true

module Mutations
  module Quotes
    class Clone < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "quotes:clone"

      graphql_name "CloneQuote"
      description "Clone a quote"

      argument :id, ID, required: true

      type Types::Quotes::Object

      def resolve(**args)
        quote = current_organization.quotes.find_by(id: args[:id])
        result = ::Quotes::CloneService.call(quote:)

        result.success? ? result.quote : result_error(result)
      end
    end
  end
end
