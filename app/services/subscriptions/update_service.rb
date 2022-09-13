# frozen_string_literal: true

module Subscriptions
  class UpdateService < BaseService
    def update(**args)
      subscription = Subscription.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'subscription') unless subscription

      subscription.name = args[:name] if args.key?(:name)

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

      subscription.save!

      result.subscription = subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
