# frozen_string_literal: true

module Mutations
  module Quotes
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "quotes:delete"

      graphql_name "DestroyQuote"
      description "Deletes a quote"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        quote = current_organization.quotes.find_by(id:)
        result = ::Quotes::DestroyService.call(quote:)

        result.success? ? result.quote : result_error(result)
      end
    end
  end
end
