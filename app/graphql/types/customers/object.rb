# frozen_string_literal: true

module Types
  module Customers
    class Object < Types::BaseObject
      graphql_name 'Customer'

      field :id, ID, null: false

      field :customer_type, Types::Customers::CustomerTypeEnum
      field :display_name, String, null: false
      field :external_id, String, null: false
      field :firstname, String
      field :lastname, String
      field :name, String
      field :sequential_id, String, null: false
      field :slug, String, null: false

      field :address_line1, String, null: true
      field :address_line2, String, null: true
      field :applicable_timezone, Types::TimezoneEnum, null: false
      field :city, String, null: true
      field :country, Types::CountryCodeEnum, null: true
      field :currency, Types::CurrencyEnum, null: true
      field :email, String, null: true
      field :external_salesforce_id, String, null: true
      field :invoice_grace_period, Integer, null: true
      field :legal_name, String, null: true
      field :legal_number, String, null: true
      field :logo_url, String, null: true
      field :net_payment_term, Integer, null: true
      field :payment_provider, Types::PaymentProviders::ProviderTypeEnum, null: true
      field :payment_provider_code, String, null: true
      field :phone, String, null: true
      field :state, String, null: true
      field :tax_identification_number, String, null: true
      field :timezone, Types::TimezoneEnum, null: true
      field :url, String, null: true
      field :zipcode, String, null: true

      field :shipping_address, Types::Customers::Address, null: true

      field :metadata, [Types::Customers::Metadata::Object], null: true

      field :billing_configuration, Types::Customers::BillingConfiguration, null: true

      field :provider_customer, Types::PaymentProviderCustomers::Provider, null: true
      field :subscriptions, [Types::Subscriptions::Object], resolver: Resolvers::Customers::SubscriptionsResolver

      field :anrok_customer, Types::IntegrationCustomers::Anrok, null: true
      field :hubspot_customer, Types::IntegrationCustomers::Hubspot, null: true
      field :netsuite_customer, Types::IntegrationCustomers::Netsuite, null: true
      field :salesforce_customer, Types::IntegrationCustomers::Salesforce, null: true
      field :xero_customer, Types::IntegrationCustomers::Xero, null: true

      field :invoices, [Types::Invoices::Object]

      field :applied_add_ons, [Types::AppliedAddOns::Object], null: true
      field :applied_coupons, [Types::AppliedCoupons::Object], null: true
      field :taxes, [Types::Taxes::Object], null: true

      field :credit_notes, [Types::CreditNotes::Object], null: true

      field :applied_dunning_campaign, Types::DunningCampaigns::Object, null: true
      field :exclude_from_dunning_campaign, Boolean, null: false
      field :last_dunning_campaign_attempt, Integer, null: false
      field :last_dunning_campaign_attempt_at, GraphQL::Types::ISO8601DateTime, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :active_subscriptions_count,
        Integer,
        null: false,
        description: 'Number of active subscriptions per customer'
      field :credit_notes_balance_amount_cents,
        GraphQL::Types::BigInt,
        null: false,
        description: 'Credit notes credits balance available per customer'
      field :credit_notes_credits_available_count,
        Integer,
        null: false,
        description: 'Number of available credits from credit notes per customer'
      field :has_active_wallet, Boolean, null: false, description: 'Define if a customer has an active wallet'
      field :has_credit_notes, Boolean, null: false, description: 'Define if a customer has any credit note'
      field :has_overdue_invoices, Boolean, null: false, description: 'Define if a customer has overdue invoices'

      field :can_edit_attributes, Boolean, null: false, method: :editable? do
        description 'Check if customer attributes are editable'
      end

      field :finalize_zero_amount_invoice, Types::Customers::FinalizeZeroAmountInvoiceEnum, null: true, description: 'Options for handling invoices with a zero total amount.'

      def invoices
        object.invoices.visible.order(created_at: :desc)
      end

      def applied_coupons
        object.applied_coupons.active.order(created_at: :asc)
      end

      def applied_add_ons
        object.applied_add_ons.order(created_at: :desc)
      end

      def has_active_wallet
        object.wallets.active.any?
      end

      def has_credit_notes
        object.credit_notes.finalized.any?
      end

      def has_overdue_invoices
        object.invoices.payment_overdue.any?
      end

      def active_subscriptions_count
        object.active_subscriptions.count
      end

      def provider_customer
        case object&.payment_provider&.to_sym
        when :stripe
          object.stripe_customer
        when :gocardless
          object.gocardless_customer
        when :adyen
          object.adyen_customer
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
          document_locale: object&.document_locale
        }
      end
    end
  end
end
