# frozen_string_literal: true

module Entitlement
  class FeatureUpdateService < BaseService
    Result = BaseResult[:feature]

    def initialize(feature:, params:, partial:)
      @feature = feature
      @params = params.to_h.with_indifferent_access
      @partial = partial
      super
    end

    activity_loggable(
      action: "feature.updated",
      record: -> { feature }
    )

    def call
      return result.not_found_failure!(resource: "feature") unless feature

      if Utils::Entitlement.privileges_param_invalid?(params[:privileges])
        return result.single_validation_failure!(field: :privileges, error_code: "value_is_invalid")
      end

      if Utils::Entitlement.privilege_code_is_duplicated?(params[:privileges])
        return result.single_validation_failure!(field: :"privilege.code", error_code: "value_is_duplicated")
      end

      return too_many_privileges_failure if too_many_new_privileges?

      ActiveRecord::Base.transaction do
        # Serializes with Entitlement::FeatureDestroyService, so a feature discarded since its lookup is not written.
        feature.lock!
        return result.not_found_failure!(resource: "feature") if feature.discarded?

        update_feature_attributes
        delete_missing_privileges unless partial?
        update_privileges
        check_privileges_limit!

        feature.save!
      end

      jobs = feature.plans.map do |plan|
        Utils::ActivityLog.produce_after_commit(plan, "plan.updated")
        SendWebhookJob.new("plan.updated", plan)
      end

      # NOTE: The webhooks are sent even if there was no actual change
      after_commit do
        ApplicationJob.perform_all_later(jobs)
        SendWebhookJob.perform_later("feature.updated", feature)
      end

      result.feature = feature
      result
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(Privilege)
        result.record_validation_failure!(record: e.record) { :"privilege.#{it}" }
      else
        result.record_validation_failure!(record: e.record)
      end
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :feature, :params, :partial
    alias_method :partial?, :partial

    # Built once, under the feature lock. The duplicate check makes sure no param reaches a privilege created later.
    def privileges_by_code
      @privileges_by_code ||= feature.privileges.index_by(&:code)
    end

    # Stored codes are stripped, so a request code reaches the privilege with the same stripped code.
    def find_privilege(code)
      privileges_by_code[Utils::Entitlement.stripped_code(code)]
    end

    def update_feature_attributes
      feature.name = params[:name] if params.key?(:name)
      feature.description = params[:description] if params.key?(:description)
    end

    def update_privileges
      return if params[:privileges].blank?

      params[:privileges].each do |privilege_params|
        privilege = find_privilege(privilege_params[:code])

        if privilege.nil?
          create_privilege(privilege_params)
        else
          privilege.name = privilege_params[:name] if privilege_params.key?(:name)

          if privilege_params.dig(:config, :select_options)
            privilege.config["select_options"] ||= []
            privilege.config["select_options"] |= privilege_params[:config][:select_options]
          end

          privilege.save!
        end
      end
    end

    def create_privilege(privilege_params)
      privilege = feature.privileges.new(
        organization: feature.organization,
        code: Utils::Entitlement.stripped_code(privilege_params[:code]),
        name: privilege_params[:name]
      )
      privilege.value_type = privilege_params[:value_type] if privilege_params.has_key? :value_type
      privilege.config = privilege_params[:config] if privilege_params.has_key? :config

      privilege.save!
      @privileges_added = true
    end

    # Cheap early refusal, before the lock and the writes: the new codes alone are above the limit whatever the
    # feature holds. The exact check stays in check_privileges_limit!.
    def too_many_new_privileges?
      return false if params[:privileges].blank?

      existing_codes = feature.privileges.pluck(:code).to_set
      new_codes = params[:privileges].count { !existing_codes.include?(Utils::Entitlement.stripped_code(it[:code])) }
      new_codes > PrivilegeCreateService::MAX_PRIVILEGES
    end

    def too_many_privileges_failure
      result.single_validation_failure!(
        field: :base,
        error_code: "too_many_privileges",
        meta: {max_items: PrivilegeCreateService::MAX_PRIVILEGES}
      )
    end

    # Counted after the removals and the creates, under the feature lock. An update that adds no privilege is
    # accepted, so a feature already above the limit stays editable. Raising rolls the whole update back.
    def check_privileges_limit!
      if @privileges_added && feature.privileges.count > PrivilegeCreateService::MAX_PRIVILEGES
        too_many_privileges_failure.raise_if_error!
      end
    end

    def delete_missing_privileges
      # Find privileges that are in the database but not in the params
      # Delete all EntitlementValues associated with those privileges
      # Then delete the privileges themselves
      kept_privilege_codes = (params[:privileges] || []).filter_map { find_privilege(it[:code])&.code }
      missing_privilege_codes = feature.privileges.pluck(:code) - kept_privilege_codes
      EntitlementValue.where(privilege: feature.privileges.where(code: missing_privilege_codes)).discard_all!
      feature.privileges.where(code: missing_privilege_codes).discard_all!
    end
  end
end
