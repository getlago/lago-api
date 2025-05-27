# frozen_string_literal: true

module Invoices
  module Preview
    class SubscriptionsService < BaseService
      Result = BaseResult[:subscriptions]

      def initialize(organization:, customer:, params:)
        @organization = organization
        @customer = customer
        @params = params
        super
      end

      def call
        return result.not_found_failure!(resource: "organization") unless organization
        return result.not_found_failure!(resource: "customer") unless customer

        if context != :proposal && customer.new_record?
          return result.single_validation_failure!(
            error_code: "must_be_persisted",
            field: :customer
          )
        end

        if [:termination, :plan_change].include?(context)
          if customer_subscriptions.size > 1
            return result.single_validation_failure!(
              error_code: "only_one_subscription_allowed_for_#{context}",
              field: :subscriptions
            )
          end
        end

        case context
        when :termination
          SubscriptionTerminationService.call(
            current_subscription:,
            terminated_at:
          )
        when :plan_change
          SubscriptionPlanChangeService.call(
            current_subscription:,
            target_plan_code:
          )
        when :proposal
          BuildSubscriptionService.call(
            customer:,
            params:
          )
        when :projection
          FindSubscriptionsService.call(
            subscriptions: customer_subscriptions
          )
        end
      end

      private

      attr_reader :params, :organization, :customer

      def context
        return @context if defined?(@context)

        @context = if external_ids.none?
          :proposal # Preview for non-existing subscription
        elsif terminated_at
          :termination
        elsif target_plan_code
          :plan_change
        else
          :projection # Preview for existing subscriptions including their next subscriptions
        end
      end

      def customer_subscriptions
        @customer_subscriptions ||= customer
          .subscriptions
          .active
          .where(external_id: external_ids)
      end

      def current_subscription
        @current_subscription ||= customer_subscriptions.first
      end

      def terminated_at
        params.dig(:subscriptions, :terminated_at)
      end

      def external_ids
        Array(params.dig(:subscriptions, :external_ids))
      end

      def target_plan_code
        params.dig(:subscriptions, :plan_code)
      end
    end
  end
end
