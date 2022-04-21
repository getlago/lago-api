# frozen_string_literal: true

module Mutations
  module Subscriptions
    class Terminate < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'TerminateSubscription'
      description 'Terminate a Subscription'

      argument :id, ID, required: true

      type Types::Subscriptions::Object

      def resolve(**args)
        validate_organization!

        result = ::Subscriptions::TerminateService.new(args[:id]).terminate

        result.success? ? result.subscription : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
