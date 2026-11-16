# frozen_string_literal: true

module Entitlement
  class PrivilegeUpdateService < BaseService
    Result = BaseResult[:privilege]

    activity_loggable(
      action: "feature.updated",
      record: -> { feature }
    )

    def initialize(feature:, privilege_code:, params:)
      @feature = feature
      @privilege_code = privilege_code
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "feature") unless feature

      # The lock serializes the option check with other updates, creates and the feature delete.
      feature.with_lock do
        return result.not_found_failure!(resource: "feature") if feature.discarded?

        # Read under the lock: a privilege loaded before it can miss an option added since.
        privilege = feature.privileges.find_by(code: privilege_code)
        return result.not_found_failure!(resource: "privilege") unless privilege

        if params.key?(:code) && stripped(params[:code]) != privilege.code
          return result.single_validation_failure!(field: :code, error_code: "value_is_immutable")
        end

        if params.key?(:value_type) && params[:value_type] != privilege.value_type
          return result.single_validation_failure!(field: :value_type, error_code: "value_is_immutable")
        end

        # select_options only belong to the select type, and are ignored for the other types.
        if privilege.value_type == "select" && params.key?(:select_options)
          # v2 replaces the list instead of merging it, so every current option must be sent again.
          removed_options = Array(privilege.config["select_options"]) - Array(params[:select_options])
          if removed_options.any?
            return result.single_validation_failure!(field: :select_options, error_code: "select_option_removal_not_allowed")
          end

          privilege.config = {"select_options" => params[:select_options]}
        end

        privilege.name = params[:name] if params.key?(:name)
        privilege.save!
        result.privilege = privilege

        SendWebhookJob.perform_after_commit("feature.updated", feature)

        # Plan payloads embed the privilege name and config, so they are sent even when nothing changed.
        jobs = feature.plans.map do |plan|
          Utils::ActivityLog.produce_after_commit(plan, "plan.updated")
          SendWebhookJob.new("plan.updated", plan)
        end
        after_commit { ApplicationJob.perform_all_later(jobs) }
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      # The v2 request has no config: the model error on it is about select_options.
      result.record_validation_failure!(record: e.record) { (it == :config) ? :select_options : it }
    end

    private

    attr_reader :feature, :privilege_code, :params

    def stripped(value)
      value.is_a?(String) ? value.strip : value
    end
  end
end
