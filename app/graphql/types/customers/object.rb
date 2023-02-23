# frozen_string_literal: true

module Types
  module Customers
    class Object < Types::BaseObject
      graphql_name 'Customer'

      field :id, ID, null: false

      field :external_id, String, null: false
      field :name, String
      field :sequential_id, String, null: false
      field :slug, String, null: false

      field :country, Types::CountryCodeEnum, null: true
      field :address_line1, String, null: true
      field :address_line2, String, null: true
      field :state, String, null: true
      field :zipcode, String, null: true
      field :email, String, null: true
      field :city, String, null: true
      field :url, String, null: true
      field :phone, String, null: true
      field :logo_url, String, null: true
      field :legal_name, String, null: true
      field :legal_number, String, null: true
      field :vat_rate, Float, null: true
      field :invoice_grace_period, Integer, null: true
      field :currency, Types::CurrencyEnum, null: true
      field :payment_provider, Types::PaymentProviders::ProviderTypeEnum, null: true
      field :timezone, Types::TimezoneEnum, null: true
      field :applicable_timezone, Types::TimezoneEnum, null: false

      field :metadata, [Types::Customers::Metadata::Object], null: true

      field :billing_configuration, Types::Customers::BillingConfiguration, null: true

      field :provider_customer, Types::PaymentProviderCustomers::Provider, null: true
      field :subscriptions, [Types::Subscriptions::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true

      field :has_active_wallet, Boolean, null: false, description: 'Define if a customer has an active wallet'
      field :has_credit_notes, Boolean, null: false, description: 'Define if a customer has any credit note'
      field :active_subscription_count, Integer, null: false, description: 'Number of active subscriptions per customer'
      field :credit_notes_credits_available_count,
            Integer,
            null: false,
            description: 'Number of available credits from credit notes per customer'
      field :credit_notes_balance_amount_cents,
            GraphQL::Types::BigInt,
            null: false,
            description: 'Credit notes credits balance available per customer'

      field :can_edit_attributes, Boolean, null: false do
        description 'Check if customer attributes are editable'
      end

      def has_active_wallet
        object.wallets.active.any?
      end

      def has_credit_notes
        object.credit_notes.finalized.any?
      end

      def active_subscription_count
        object.active_subscriptions.count
      end

      def can_edit_attributes
        object.editable?
      end

      def provider_customer
        case object&.payment_provider&.to_sym
        when :stripe
          object.stripe_customer
        when :gocardless
          object.gocardless_customer
        end
      end

      def credit_notes_credits_available_count
        object.credit_notes.finalized.where('credit_notes.credit_amount_cents > 0').count
      end

      def credit_notes_balance_amount_cents
        object.credit_notes.finalized.sum('credit_notes.balance_amount_cents')
      end

      def billing_configuration
        {
          id: "#{object&.id}-c0nf",
          document_locale: object&.document_locale,
        }
      end
    end
  end
end
