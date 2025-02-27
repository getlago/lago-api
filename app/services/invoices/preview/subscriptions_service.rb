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
        return result.not_found_failure!(resource: "customer") unless customer

        result.subscriptions = handle_subscriptions
        result
      rescue ActiveRecord::RecordNotFound => exception
        result.not_found_failure!(resource: exception.model.demodulize.underscore)
        result
      end

      private

      attr_reader :params, :organization, :customer

      def handle_subscriptions
        return handle_customer_subscriptions if external_ids.any?

        plan ? [build_subscription] : []
      end

      def handle_customer_subscriptions
        terminated_at ? terminate_subscriptions : customer_subscriptions
      end

      def terminate_subscriptions
        return [] unless valid_termination?

        customer_subscriptions.map do |subscription|
          subscription.terminated_at = terminated_at
          subscription.status = :terminated
          subscription
        end
      end

      def build_subscription
        Subscription.new(
          customer: customer,
          plan:,
          subscription_at: params[:subscription_at].presence || Time.current,
          started_at: params[:subscription_at].presence || Time.current,
          billing_time:,
          created_at: params[:subscription_at].presence || Time.current,
          updated_at: Time.current
        )
      end

      def billing_time
        if Subscription::BILLING_TIME.include?(params[:billing_time]&.to_sym)
          params[:billing_time]
        else
          "calendar"
        end
      end

      def customer_subscriptions
        @customer_subscriptions ||= customer
          .subscriptions
          .active
          .where(external_id: external_ids)
      end

      def valid_termination?
        if customer_subscriptions.size > 1
          result.single_validation_failure!(
            error_code: "only_one_subscription_allowed_for_termination",
            field: :subscriptions
          )
        end

        if parsed_terminated_at&.to_date&.past?
          result.single_validation_failure!(
            error_code: "cannot_be_in_past",
            field: :terminated_at
          )
        end

        result.success?
      end

      def parsed_terminated_at
        if Utils::Datetime.valid_format?(terminated_at)
          Time.zone.parse(terminated_at)
        else
          result.single_validation_failure!(error_code: "invalid_timestamp", field: :terminated_at)
          nil
        end
      end

      def terminated_at
        params.dig(:subscriptions, :terminated_at)
      end

      def external_ids
        Array(params.dig(:subscriptions, :external_ids))
      end

      def plan
        organization.plans.find_by!(code: params[:plan_code])
      end
    end
  end
end
