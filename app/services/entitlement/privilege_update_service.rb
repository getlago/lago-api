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

      # The v2 controller passes these raw, so an array, an object or a number is refused here.
      invalid_field = %i[code name value_type].find { !params[it].nil? && !params[it].is_a?(String) }
      return result.single_validation_failure!(field: invalid_field, error_code: "value_is_invalid") if invalid_field

      # The lock serializes the option check with other updates, creates and the feature delete.
      feature.with_lock do
        return result.not_found_failure!(resource: "feature") if feature.discarded?

        # Read under the lock: a privilege loaded before it can miss an option added since.
        privilege = feature.privileges.find_by(code: privilege_code)
        return result.not_found_failure!(resource: "privilege") unless privilege

        if params.key?(:code) && params[:code]&.strip != privilege.code
          return result.single_validation_failure!(field: :code, error_code: "value_is_immutable")
        end

        if params.key?(:value_type) && params[:value_type] != privilege.value_type
          return result.single_validation_failure!(field: :value_type, error_code: "value_is_immutable")
        end

        if params.key?(:select_options)
          select_result = ValidatePrivilegeSelectOptionsService.call(value_type: privilege.value_type, params:)
          return result.fail_with_error!(select_result.error) unless select_result.success?

          # v2 replaces the list instead of merging it, so every current option must be sent again.
          removed_options = Array(privilege.config["select_options"]) - Array(select_result.config["select_options"])
          if removed_options.any?
            return result.single_validation_failure!(field: :select_options, error_code: "select_option_removal_not_allowed")
          end

          privilege.config = select_result.config
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
  end
end
