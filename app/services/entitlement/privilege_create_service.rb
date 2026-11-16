# frozen_string_literal: true

module Entitlement
  class PrivilegeCreateService < BaseService
    Result = BaseResult[:privilege]

    MAX_PRIVILEGES = 50

    activity_loggable(
      action: "feature.updated",
      record: -> { feature }
    )

    def initialize(feature:, params:)
      @feature = feature
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "feature") unless feature

      # The v2 controller passes these raw, so an array, an object or a number is refused here.
      invalid_field = %i[code name].find { !params[it].nil? && !params[it].is_a?(String) }
      return result.single_validation_failure!(field: invalid_field, error_code: "value_is_invalid") if invalid_field

      unless Privilege::VALUE_TYPES.include?(value_type)
        return result.single_validation_failure!(
          field: :value_type,
          error_code: "value_is_invalid",
          meta: {allowed_values: Privilege::VALUE_TYPES}
        )
      end

      select_result = ValidatePrivilegeSelectOptionsService.call(value_type:, params:)
      return result.fail_with_error!(select_result.error) unless select_result.success?

      # The lock serializes the count and the insert with other creates and with the feature delete.
      feature.with_lock do
        return result.not_found_failure!(resource: "feature") if feature.discarded?

        if feature.privileges.count >= MAX_PRIVILEGES
          return result.single_validation_failure!(
            field: :base,
            error_code: "too_many_privileges",
            meta: {max_items: MAX_PRIVILEGES}
          )
        end

        result.privilege = feature.privileges.create!(
          organization_id: feature.organization_id,
          code: params[:code]&.strip,
          name: params[:name],
          value_type:,
          config: select_result.config
        )

        SendWebhookJob.perform_after_commit("feature.updated", feature)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      # The v2 request has no config: the model error on it is about select_options.
      result.record_validation_failure!(record: e.record) { (it == :config) ? :select_options : it }
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, "idx_privileges_code_unique_per_feature" => :code)
    end

    private

    attr_reader :feature, :params

    def value_type
      params[:value_type] || "string"
    end
  end
end
