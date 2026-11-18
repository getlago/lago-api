# frozen_string_literal: true

module RecurringAggregationSnapshots
  class DeleteService < BaseService
    Result = BaseResult

    def initialize(subscription:)
      @subscription = subscription

      super
    end

    # Only the subscription and the one following it read its snapshots: once it ends without a next
    # one, nothing reads them, and the pruning of a later write never comes.
    def call
      RecurringAggregationSnapshot.where(organization_id: subscription.organization_id, subscription_id: subscription.id).delete_all

      result
    end

    private

    attr_reader :subscription
  end
end
