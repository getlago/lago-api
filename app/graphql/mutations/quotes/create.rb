# frozen_string_literal: true

module Mutations
  module Quotes
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "quotes:create"

      graphql_name "CreateQuote"
      description "Create a new quote"

      input_object_class Types::Quotes::CreateInput

      type Types::Quotes::Object

      def resolve(**args)
        result = ::Quotes::CreateService.call(
          organization: current_organization,
          params: args
        )

        result.success? ? result.quote : result_error(result)
      end
    end
  end
end
