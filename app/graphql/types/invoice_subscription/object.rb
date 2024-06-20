# frozen_string_literal: true

module Types
  module InvoiceSubscription
    class Object < Types::BaseObject
      graphql_name 'InvoiceSubscription'

      field :invoice, Types::Invoices::Object, null: false
      field :subscription, Types::Subscriptions::Object, null: false

      field :charge_amount_cents, GraphQL::Types::BigInt, null: false
      field :subscription_amount_cents, GraphQL::Types::BigInt, null: false
      field :total_amount_cents, GraphQL::Types::BigInt, null: false

      field :fees, [Types::Fees::Object], null: true

      field :charges_from_datetime, GraphQL::Types::ISO8601DateTime, null: true
      field :charges_to_datetime, GraphQL::Types::ISO8601DateTime, null: true

      field :in_advance_charges_from_datetime, GraphQL::Types::ISO8601DateTime, null: true
      field :in_advance_charges_to_datetime, GraphQL::Types::ISO8601DateTime, null: true

      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: true
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: true

      def in_advance_charges_from_datetime
        return nil unless should_use_in_advance_charges_interval

        charge_pay_in_advance_interval[:charges_from_date]
      end

      def in_advance_charges_to_datetime
        return nil unless should_use_in_advance_charges_interval

        charge_pay_in_advance_interval[:charges_to_date]
      end

      def should_use_in_advance_charges_interval
        return @should_use_in_advance_charges_interval if defined? @should_use_in_advance_charges_interval

        @should_use_in_advance_charges_interval =
          object.fees.charge_kind.any? &&
          object.subscription.plan.charges.where(pay_in_advance: true).any? &&
          !object.subscription.plan.pay_in_advance?
      end

      def charge_pay_in_advance_interval
        @charge_pay_in_advance_interval ||=
          ::Subscriptions::DatesService.charge_pay_in_advance_interval(object.timestamp, object.subscription)
      end
    end
  end
end
