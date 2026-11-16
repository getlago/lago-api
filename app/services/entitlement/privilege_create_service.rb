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

        result.privilege = feature.privileges.create!(attributes)

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

    # The model validates the values. A missing value_type keeps the column default (string), and
    # select_options only belong to the select type.
    def attributes
      code = params[:code]
      value_type = params[:value_type]

      {
        organization_id: feature.organization_id,
        code: code.is_a?(String) ? code.strip : code,
        name: params[:name],
        config: (value_type == "select") ? {"select_options" => params[:select_options]} : {}
      }.tap { it[:value_type] = value_type unless value_type.nil? }
    end
  end
end
