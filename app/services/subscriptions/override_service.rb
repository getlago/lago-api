# frozen_string_literal: true

module Subscriptions
  class OverrideService < BaseService
    include ChargeModelAttributesHandler

    def call(**args)
      ActiveRecord::Base.transaction do
        plan_params = handle_plan_args(args)

        plan_result = ::Plans::CreateService.new.create(**plan_params)

        return failed_plan_creation_result(plan_result) unless plan_result.success?

        subscription_params = handle_subscription_args(args, plan_result.plan.id)
        subscription_result = ::Subscriptions::CreateService.new.create(**subscription_params)

        return failed_subscription_creation_result(subscription_result) unless subscription_result.success?

        result.subscription = subscription_result.subscription
      end

      result
    end

    private

    def handle_plan_args(args)
      params = args[:plan]
      params[:code] = "#{params[:code]}-#{SecureRandom.uuid}"

      prepare_arguments(**params)
        .merge(overridden_plan_id: args[:overridden_plan_id])
        .merge(organization_id: args[:organization_id])
    end

    def handle_subscription_args(args, plan_id)
      args.delete(:plan)
      args.delete(:overridden_plan_id)
      args[:plan_id] = plan_id

      args
    end

    def failed_plan_creation_result(plan_result)
      if plan_result.error_code == 'not_found'
        result.fail!(
          code: 'not_found',
          message: 'Some resources have not been found while overriding plan',
          details: plan_result.error_details,
        )
      else
        result.fail!(
          code: 'unprocessable_entity',
          message: 'Validation error happened while overriding plan',
          details: plan_result.error_details,
        )
      end
    end

    def failed_subscription_creation_result(subscription_result)
      if subscription_result.error_code == 'missing_argument'
        result.fail!(
          code: 'not_found',
          message: 'Some resources have not been found while creating subscription',
          details: subscription_result.error_details,
        )
      elsif subscription_result.error_code == 'currencies_does_not_match'
        result.fail!(
          code: 'currencies_does_not_match',
          message: 'Currency has been overridden to invalid value',
          details: subscription_result.error_details,
        )
      else
        result.fail!(
          code: 'unprocessable_entity',
          message: 'Validation error on the record while creating subscription',
          details: subscription_result.error_details,
        )
      end
    end
  end
end
