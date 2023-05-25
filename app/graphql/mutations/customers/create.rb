# frozen_string_literal: true

module Mutations
  module Customers
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateCustomer'
      description 'Creates a new customer'

      argument :address_line1, String, required: false
      argument :address_line2, String, required: false
      argument :city, String, required: false
      argument :country, Types::CountryCodeEnum, required: false
      argument :currency, Types::CurrencyEnum, required: false
      argument :email, String, required: false
      argument :external_id, String, required: true
      argument :invoice_grace_period, Integer, required: false
      argument :legal_name, String, required: false
      argument :legal_number, String, required: false
      argument :logo_url, String, required: false
      argument :name, String, required: true
      argument :phone, String, required: false
      argument :state, String, required: false
      argument :timezone, Types::TimezoneEnum, required: false
      argument :url, String, required: false
      argument :vat_rate, Float, required: false
      argument :zipcode, String, required: false

      argument :metadata, [Types::Customers::Metadata::Input], required: false

      argument :payment_provider, Types::PaymentProviders::ProviderTypeEnum, required: false
      argument :provider_customer, Types::PaymentProviderCustomers::ProviderInput, required: false

      argument :billing_configuration, Types::Customers::BillingConfigurationInput, required: false

      type Types::Customers::Object

      def resolve(**args)
        validate_organization!

        result = ::Customers::CreateService
          .new(context[:current_user])
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.customer : result_error(result)
      end
    end
  end
end
