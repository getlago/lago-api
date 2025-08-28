# frozen_string_literal: true

module Types
  module Subscriptions
    class Object < Types::BaseObject
      graphql_name "Subscription"

      field :customer, Types::Customers::Object, null: false
      field :external_id, String, null: false
      field :id, ID, null: false
      field :plan, Types::Plans::Object, null: false

      field :name, String, null: true
      field :period_end_date, GraphQL::Types::ISO8601Date
      field :status, Types::Subscriptions::StatusTypeEnum

      field :billing_time, Types::Subscriptions::BillingTimeEnum
      field :canceled_at, GraphQL::Types::ISO8601DateTime
      field :ending_at, GraphQL::Types::ISO8601DateTime
      field :on_termination_credit_note, Types::Subscriptions::OnTerminationCreditNoteEnum
      field :on_termination_invoice, Types::Subscriptions::OnTerminationInvoiceEnum, null: false
      field :started_at, GraphQL::Types::ISO8601DateTime
      field :subscription_at, GraphQL::Types::ISO8601DateTime
      field :terminated_at, GraphQL::Types::ISO8601DateTime

      field :current_billing_period_ending_at, GraphQL::Types::ISO8601DateTime
      field :current_billing_period_started_at, GraphQL::Types::ISO8601DateTime

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :next_name, String, null: true
      field :next_plan, Types::Plans::Object
      field :next_subscription, Types::Subscriptions::Object
      field :next_subscription_at, GraphQL::Types::ISO8601DateTime
      field :next_subscription_type, Types::Subscriptions::NextSubscriptionTypeEnum

      field :activity_logs, [Types::ActivityLogs::Object], null: true
      field :fees, [Types::Fees::Object], null: true

      field :lifetime_usage, Types::Subscriptions::LifetimeUsageObject, null: true

      def next_plan
        object.next_subscription&.plan
      end

      def next_name
        object.next_subscription&.name
      end

      def next_subscription_type
        if object.upgraded?
          "upgrade"
        elsif object.downgraded?
          "downgrade"
        end
      end

      def next_subscription_at
        object.next_subscription&.started_at || object.next_subscription&.subscription_at
      end

      def period_end_date
        ::Subscriptions::DatesService.new_instance(object, Time.current)
          .next_end_of_period
      end

      def lifetime_usage
        return nil unless object.plan.usage_thresholds.any? || object.organization.lifetime_usage_enabled?

        object.lifetime_usage
      end

      def current_billing_period_started_at
        dates_service.charges_from_datetime
      end

      def current_billing_period_ending_at
        dates_service.charges_to_datetime
      end

      def dates_service
        @dates_service ||= ::Subscriptions::DatesService.new_instance(object, Time.current, current_usage: true)
      end
    end
  end
end
