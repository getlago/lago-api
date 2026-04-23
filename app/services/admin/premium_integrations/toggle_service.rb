# frozen_string_literal: true

module Admin
  module PremiumIntegrations
    class ToggleService < ::BaseService
      Result = BaseResult[:organization, :activity_log]

      MAX_REASON_LENGTH = 1000

      REASON_CATEGORIES = %w[
        trial_enablement
        customer_support
        bug_workaround
        sales_demo
        other
      ].freeze

      # Which premium integrations each staff role is allowed to toggle.
      # :admin => all PREMIUM_INTEGRATIONS; any other role => a fixed safe subset.
      ROLE_ALLOWED_INTEGRATIONS = {
        admin: :all,
        cs: %w[
          remove_branding_watermark
          auto_dunning
          revenue_analytics
          analytics_dashboards
          from_email
          issue_receipts
          preview
        ].freeze
      }.freeze

      def initialize(organization:, integration:, enabled:, reason:, reason_category:, admin_user:, staff_role:)
        @organization = organization
        @integration = integration.to_s
        @enabled = enabled
        @reason = reason.to_s.strip
        @reason_category = reason_category.to_s
        @admin_user = admin_user
        @staff_role = staff_role&.to_sym

        super
      end

      def call
        return result.not_found_failure!(resource: "organization") unless organization
        return result.single_validation_failure!(field: :integration, error_code: "invalid_integration") unless valid_integration?
        return result.single_validation_failure!(field: :reason, error_code: "value_is_mandatory") if reason.blank?
        return result.single_validation_failure!(field: :reason, error_code: "value_is_too_long") if reason.length > MAX_REASON_LENGTH
        return result.single_validation_failure!(field: :reason_category, error_code: "invalid_reason_category") unless valid_reason_category?
        return result.forbidden_failure!(code: "integration_not_allowed_for_role") unless role_can_toggle?

        previous_integrations = organization.premium_integrations.dup
        next_integrations = compute_next_integrations(previous_integrations)

        if previous_integrations.sort == next_integrations.sort
          result.organization = organization
          return result
        end

        ActiveRecord::Base.transaction do
          organization.update!(premium_integrations: next_integrations)
          result.activity_log = write_activity_log(previous_integrations, next_integrations)
        end

        notify_slack_async(previous_integrations, next_integrations)

        result.organization = organization
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :organization, :integration, :enabled, :reason, :reason_category, :admin_user, :staff_role

      def valid_integration?
        Organization::PREMIUM_INTEGRATIONS.include?(integration)
      end

      def valid_reason_category?
        REASON_CATEGORIES.include?(reason_category)
      end

      def role_can_toggle?
        allowed = ROLE_ALLOWED_INTEGRATIONS[staff_role]
        return false if allowed.nil?
        return true if allowed == :all

        allowed.include?(integration)
      end

      def compute_next_integrations(previous)
        if enabled
          (previous + [integration]).uniq
        else
          previous - [integration]
        end
      end

      def write_activity_log(previous, current)
        Clickhouse::ActivityLog.create!(
          activity_type: Clickhouse::ActivityLog::ACTIVITY_TYPES[:organization_premium_integration_toggled],
          activity_source: "api",
          activity_object: {
            organization_id: organization.id,
            integration: integration
          }.stringify_keys.transform_values { |v| v.to_json },
          activity_object_changes: {
            integration: integration,
            enabled: enabled,
            reason: reason,
            reason_category: reason_category,
            staff_role: staff_role.to_s,
            admin_user_id: admin_user&.id,
            admin_user_email: admin_user&.email,
            previous_integrations: previous,
            current_integrations: current
          }.stringify_keys.transform_values { |v| v.to_json },
          organization_id: organization.id,
          user_id: nil,
          resource_type: "Organization",
          resource_id: organization.id,
          logged_at: Time.current,
          created_at: Time.current
        )
      end

      def notify_slack_async(previous, current)
        return if ENV["LAGO_STAFF_SLACK_WEBHOOK"].blank?

        ::Admin::PremiumIntegrations::NotifySlackJob.perform_later(
          organization_id: organization.id,
          organization_name: organization.name,
          integration: integration,
          enabled: enabled,
          reason: reason,
          reason_category: reason_category,
          actor_email: admin_user&.email,
          staff_role: staff_role.to_s,
          previous_integrations: previous,
          current_integrations: current
        )
      rescue => e
        Rails.logger.warn("Failed to enqueue NotifySlackJob: #{e.message}")
      end
    end
  end
end
