# frozen_string_literal: true

module Subscriptions
  module RateSchedules
    class SubscribeService < BaseService
      Result = BaseResult[:subscription, :payment_method]

      def initialize(customer:, plan:, params:)
        super

        @customer = customer
        @plan = plan
        @params = params

        params[:subscription_at] ||= Time.current
        params[:external_id] = params[:external_id].to_s.strip
      end

      # NOTE: add a service for creating a subscription from API 
      # that creates a new customer if it does not exist
      # TODO: add support for overrides
      def call
        return result unless valid_params?

        customer.with_lock do
          subscription = subscribe_to_plan

          if params[:usage_thresholds].present?
            UpdateUsageThresholdsService.call!(
              subscription:,
              usage_thresholds_params: params[:usage_thresholds],
              partial: false
            )
          end

          InvoiceCustomSections::AttachToResourceService.call(resource: subscription, params:) unless downgrade?

          result.subscription = subscription
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ArgumentError
        result.validation_failure!(errors: {billing_time: ["value_is_invalid"]})
      rescue BaseService::FailedResult => e
        e.result
      end

      private

      attr_reader :customer, :plan, :params, :external_id

      def valid_params?
        result.payment_method = payment_method

        Subscriptions::ValidateService.new(
          result, 
          customer:,
          plan:,
          subscription_at: params[:subscription_at],
          ending_at: params[:ending_at],
          payment_method: params[:payment_method]
        ).valid?

        if params[:external_customer_id].blank? && api_context?
          result.validation_failure!(errors: {external_customer_id: ["value_is_mandatory"]}) 
        end

        result.success?
      end

      def payment_method
        return @payment_method if defined? @payment_method
        return nil if params[:payment_method].blank? || params[:payment_method][:payment_method_id].blank?

        @payment_method = PaymentMethod.find_by(
          id: params[:payment_method][:payment_method_id],
          organization_id: customer.organization_id
        )
      end

      def subscribe_to_plan
        subscription = current_subscription

        if upgrade?(subscription)
          upgrade_plan(subscription)
        elsif downgrade?(subscription)
          downgrade_plan(subscription)
        else
          subscription || create_subscription
        end
      end

      def current_subscription
        customer.subscriptions.active
          .or(customer.subscriptions.starting_in_the_future)
          .order(started_at: :desc)
          .find_by(
            "id = :id OR external_id = :external_id", 
            id: params[:subscription_id], 
            external_id: params[:external_id]
          )
      end

      def upgrade?(subscription)
        return false unless subscription
        return false if plan.id == subscription.plan.id

        plan.yearly_amount_cents >= subscription.plan.yearly_amount_cents
      end

      def downgrade?(subscription)
        return false unless subscription
        return false if plan.id == subscription.plan.id

        plan.yearly_amount_cents < subscription.plan.yearly_amount_cents
      end

      def upgrade_plan(subscription)
        PlanUpgradeService.call!(subscription:, plan:, params:).subscription
      end

      def downgrade_plan(subscription)
        PlanDowngradeService.call!(subscription:, plan:, params:).subscription
      end

      def create_subscription
        CreateService.call!(customer:, plan:, params:).subscription
      end
    end
  end
end
