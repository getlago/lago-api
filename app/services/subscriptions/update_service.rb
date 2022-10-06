# frozen_string_literal: true

module Subscriptions
  class UpdateService < BaseService
    def update(**args)
      subscription = Subscription.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'subscription') unless subscription

      subscription.name = args[:name] if args.key?(:name)

      if subscription.starting_in_the_future? && args.key?(:subscription_date)
        subscription.subscription_date = args[:subscription_date]

        process_subscription_date_change(subscription)
      else
        subscription.save!
      end

      result.subscription = subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def update_from_api(organization:, external_id:, params:)
      subscription = organization.subscriptions.find_by(external_id: external_id)
      return result.not_found_failure!(resource: 'subscription') unless subscription

      subscription.name = params[:name] if params.key?(:name)

      if subscription.starting_in_the_future? && params.key?(:subscription_date)
        subscription.subscription_date = params[:subscription_date]

        process_subscription_date_change(subscription)
      else
        subscription.save!
      end

      result.subscription = subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def process_subscription_date_change(subscription)
      if subscription.subscription_date <= Time.current.to_date
        subscription.mark_as_active!(subscription.subscription_date.beginning_of_day)
      else
        subscription.save!
      end

      return unless subscription.plan.pay_in_advance? && subscription.subscription_date.today?

      BillSubscriptionJob.perform_later([subscription], Time.current.to_i)
    end
  end
end
