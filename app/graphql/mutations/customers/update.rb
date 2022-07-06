# frozen_string_literal: true

module Mutations
  module Customers
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateCustomer'
      description 'Updates an existing Customer'

      argument :id, ID, required: true
      argument :name, String, required: true
      argument :customer_id, String, required: true
      argument :country, Types::CountryCodeEnum, required: false
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
      argument :vat_rate, Float, required: false
      argument :payment_provider, Types::PaymentProviders::ProviderTypeEnum, required: false

      argument :stripe_customer, Types::PaymentProviderCustomers::StripeInput, required: false

      type Types::Customers::Object

      def resolve(**args)
        result = ::Customers::UpdateService.new(context[:current_user]).update(**args)

        result.success? ? result.customer : result_error(result)
      end
    end
  end
end
