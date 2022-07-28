# frozen_string_literal: true

module Subscriptions
  class UpdateService < BaseService
    def update(**args)
      subscription = Subscription.find_by(id: args[:id])
      return result.fail!('not_found') unless subscription

      subscription.name = args[:name] if args.key?(:name)

      subscription.save!

      result.subscription = subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
