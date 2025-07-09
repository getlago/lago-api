# frozen_string_literal: true

module Entitlement
  class PrivilegeDestroyService < BaseService
    Result = BaseResult[:privilege]

    def initialize(privilege:)
      @privilege = privilege
      super
    end

    def call
      return result.not_found_failure!(resource: "privilege") unless privilege

      jobs = privilege.entitlements.select(:plan_id).distinct.pluck(:plan_id).map do |plan_id|
        SendWebhookJob.new("plan.updated", Plan.new(id: plan_id))
      end

      ActiveRecord::Base.transaction do
        privilege.values.discard_all!
        privilege.discard!
      end

      after_commit { ActiveJob.perform_all_later(jobs) }

      SendWebhookJob.perform_after_commit("feature.updated", privilege.feature)

      result.privilege = privilege
      result
    end

    private

    attr_reader :privilege
  end
end
