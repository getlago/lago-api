# frozen_string_literal: true

module UsageMonitoring
  class TrackSubscriptionActivityService < BaseService
    Result = BaseResult

    def initialize(organization:, subscription_ids:)
      @organization = organization
      @subscription_ids = Array.wrap(subscription_ids)
      super()
    end

    def call
      return unless organization.tracks_subscription_activity?

      activities = []
      subscription_ids.each do |id|
        activities << {organization_id: organization.id, subscription_id: id}
      end

      UsageMonitoring::SubscriptionActivity.insert_all(activities, unique_by: :idx_subscription_unique) # rubocop:disable Rails/SkipsModelValidations

      result
    end

    private

    attr_reader :organization, :subscription_ids
  end
end
