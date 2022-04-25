# frozen_string_literal: true

module Mutations
  module Subscriptions
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateSubscription'
      description 'Create a new Subscription'

      argument :customer_id, String, required: true
      argument :plan_code, String, required: true

      argument :country, Types::Customers::CountryCodeEnum, required: false
      argument :address_line1, String, required: false
      argument :address_line2, String, required: false
      argument :state, String, required: false
      argument :zipcode, String, required: false
      argument :email, String, required: false
      argument :city, String, required: false
      argument :url, String, required: false
      argument :phone, String, required: false
      argument :logo_url, String, required: false
      argument :legal_name, String, required: false
      argument :legal_number, String, required: false

      type Types::Subscriptions::Object

      def resolve(**args)
        validate_organization!

        result = SubscriptionsService
          .new
          .create(
            organization: current_organization,
            params: args,
          )

        result.success? ? result.subscription : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
