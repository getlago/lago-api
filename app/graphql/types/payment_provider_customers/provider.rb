# frozen_string_literal: true

module Types
  module PaymentProviderCustomers
    class Provider < Types::BaseObject
      graphql_name "ProviderCustomer"

      field :code, String, null: true
      field :id, ID, null: false
      field :is_default, Boolean, null: false
      field :payment_methods, resolver: Resolvers::PaymentProviderCustomers::PaymentMethodsResolver
      field :payment_provider, Types::PaymentProviders::ProviderTypeEnum, null: true
      field :payment_provider_code, String, null: true
      field :provider_customer_id, ID, null: true
      field :provider_payment_methods, [Types::PaymentProviderCustomers::ProviderPaymentMethodsEnum], null: true
      field :sync_with_provider, Boolean, null: true

      # The table also holds provider-less rows (the STI base class, no
      # association): both fields resolve to nil there instead of assuming
      # a provider exists.
      def payment_provider
        provider_type = object.type.demodulize.underscore.delete_suffix("_customer")

        ::Customer::PAYMENT_PROVIDERS.include?(provider_type) ? provider_type : nil
      end

      def payment_provider_code
        dataloader.with(Sources::ActiveRecordAssociation, :payment_provider).load(object)&.code
      end
    end
  end
end
