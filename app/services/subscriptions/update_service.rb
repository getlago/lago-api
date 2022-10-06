# frozen_string_literal: true

module Subscriptions
  class UpdateService < BaseService
    def update(**args)
      subscription = Subscription.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'subscription') unless subscription

      subscription.name = args[:name] if args.key?(:name)

      if subscription.starting_in_the_future?
        subscription.subscription_date = args[:subscription_date] if args.key?(:subscription_date)
      end

      subscription.save!

      result.subscription = subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def update_from_api(organization:, external_id:, params:)
      subscription = organization.subscriptions.find_by(external_id: external_id)
      return result.not_found_failure!(resource: 'subscription') unless subscription

      subscription.name = params[:name] if params.key?(:name)

      if subscription.starting_in_the_future?
        subscription.subscription_date = params[:subscription_date] if params.key?(:subscription_date)
      end

      subscription.save!

      result.subscription = subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
