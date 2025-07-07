# frozen_string_literal: true

module Entitlement
  class FeatureBaseUpdateService < BaseService
    Result = BaseResult[:feature]

    def call
      raise NotImplementedError, "This method should be overridden in subclasses"
    end

    def initialize(feature:, params:)
      @feature = feature
      @params = params.to_h.with_indifferent_access
      super
    end

    private

    attr_reader :feature, :params

    def handle_validation_and_webhooks
      return result.not_found_failure!(resource: "feature") unless feature

      jobs = feature.entitlements.select(:plan_id).distinct.pluck(:plan_id).map do |plan_id|
        SendWebhookJob.new("plan.updated", Plan.new(id: plan_id))
      end

      yield

      # NOTE: The webhook is sent even if there was no actual change
      after_commit { ActiveJob.perform_all_later(jobs) }

      SendWebhookJob.perform_after_commit("feature.updated", feature)

      result.feature = feature
      result
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(Privilege)
        errors = e.record.errors.messages.transform_keys { |key| :"privilege.#{key}" }
        result.validation_failure!(errors:)
      else
        result.record_validation_failure!(record: e.record)
      end
    end

    def update_feature_attributes
      feature.name = params[:name] if params.key?(:name)
      feature.description = params[:description] if params.key?(:description)
    end

    def update_privileges
      params[:privileges].each do |code, privilege_params|
        privilege = feature.privileges.find { it[:code] == code }

        if privilege.nil?
          create_privilege(code, privilege_params)
        else
          privilege.name = privilege_params[:name] if privilege_params.key?(:name)
          privilege.save!
        end
      end
    end

    def create_privilege(code, privilege_params)
      privilege = feature.privileges.new(
        organization: feature.organization,
        code: code,
        name: privilege_params[:name]
      )
      privilege.value_type = privilege_params[:value_type] || "string"
      privilege.config = privilege_params[:config] if privilege_params.has_key? :config # Use DB default if not set

      privilege.save!
    end
  end
end
