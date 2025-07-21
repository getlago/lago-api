# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlementsUpdateService < BaseService
    Result = BaseResult

    def initialize(organization:, subscription:, entitlements_params:, partial:)
      @organization = organization
      @subscription = subscription
      @entitlements_params = entitlements_params.to_h.with_indifferent_access
      @partial = partial
      super
    end

    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription }
    )

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "subscription") unless subscription

      ActiveRecord::Base.transaction do
        delete_missing_entitlements unless partial?
        update_entitlements
      end

      # NOTE: The webhooks is sent even if no changes were made to the subscription
      SendWebhookJob.perform_after_commit("subscription.updated", subscription)

      result
    rescue ValidationFailure => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(Entitlement::EntitlementValue)
        errors = e.record.errors.messages.transform_keys { |key| :"privilege.#{key}" }
        result.validation_failure!(errors:)
      else
        result.record_validation_failure!(record: e.record)
      end
    rescue ActiveRecord::RecordNotFound => e
      if e.message.include?("Entitlement::Feature")
        result.not_found_failure!(resource: "feature")
      elsif e.message.include?("Entitlement::Privilege")
        result.not_found_failure!(resource: "privilege")
      else
        result.not_found_failure!(resource: "record")
      end
    end

    private

    attr_reader :organization, :subscription, :entitlements_params, :partial
    alias_method :partial?, :partial

    def delete_missing_entitlements
      missing = subscription.entitlements.joins(:feature).where.not(feature: {code: entitlements_params.keys})
      EntitlementValue.where(entitlement: missing).discard_all!
      missing.discard_all!
    end

    def delete_missing_entitlement_values(entitlement, privilege_values)
      return if privilege_values.blank?

      entitlement.values.joins(:privilege).where.not(privilege: {code: privilege_values.keys}).discard_all!
    end

    def update_entitlements
      return if entitlements_params.blank?

      entitlements_params.each do |feature_code, privilege_values|
        feature = organization.features.includes(:privileges).find { it.code == feature_code }

        raise ActiveRecord::RecordNotFound.new("Entitlement::Feature") unless feature

        entitlement = subscription.entitlements.includes(:values).find { it.entitlement_feature_id == feature.id }

        if entitlement.nil?
          entitlement = Entitlement.create!(
            organization: organization,
            feature: feature,
            subscription_id: subscription.id
          )
        elsif !partial?
          delete_missing_entitlement_values(entitlement, privilege_values)
        end

        update_entitlement_values(entitlement, feature, privilege_values)
      end
    end

    def create_entitlement_values(entitlement, feature, privilege_values)
      privilege_values.each do |privilege_code, value|
        privilege = feature.privileges.find { it.code == privilege_code }

        raise ActiveRecord::RecordNotFound.new("Entitlement::Privilege") unless privilege

        create_entitlement_value(entitlement, privilege, value)
      end
    end

    def update_entitlement_values(entitlement, feature, privilege_values)
      return if privilege_values.blank?

      privilege_values.each do |privilege_code, value|
        privilege = feature.privileges.find { it.code == privilege_code }

        raise ActiveRecord::RecordNotFound.new("Entitlement::Privilege") unless privilege

        entitlement_value = entitlement.values.find { it.entitlement_privilege_id == privilege.id }

        if entitlement_value
          entitlement_value.update!(value: validate_and_stringify(value, privilege))
        else
          create_entitlement_value(entitlement, privilege, value)
        end
      end
    end

    def create_entitlement_value(entitlement, privilege, value)
      EntitlementValue.create!(
        organization: organization,
        entitlement: entitlement,
        privilege: privilege,
        value: validate_and_stringify(value, privilege)
      )
    end

    def validate_and_stringify(value, privilege)
      return value if value.nil?

      if privilege.value_type == "select"
        unless privilege.config.dig("select_options").include?(value)
          raise ValidationFailure.new(result, messages: {"#{privilege.code}_privilege_value": ["value_not_in_select_options"]})
        end
      end

      if value.is_a?(String) || value.is_a?(Integer) || [true, false].include?(value)
        value.to_s
      else
        raise ValidationFailure.new(result, messages: {"#{privilege.code}_privilege_value": ["value_is_invalid"]})
      end
    end
  end
end
