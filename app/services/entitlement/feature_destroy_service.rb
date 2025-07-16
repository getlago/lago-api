# frozen_string_literal: true

module Entitlement
  class FeatureDestroyService < BaseService
    Result = BaseResult[:feature]

    def initialize(feature:)
      @feature = feature
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "feature") unless feature

      jobs = feature.entitlements.select(:plan_id).distinct.pluck(:plan_id).map do |plan_id|
        SendWebhookJob.new("plan.updated", Plan.new(id: plan_id))
      end

      ActiveRecord::Base.transaction do
        feature.entitlement_values.discard_all!
        feature.entitlements.discard_all!
        feature.privileges.discard_all!
        feature.discard!
      end

      after_commit { ActiveJob.perform_all_later(jobs) }

      SendWebhookJob.perform_after_commit("feature.deleted", feature)

      result.feature = feature
      result
    end

    private

    attr_reader :feature
  end
end
