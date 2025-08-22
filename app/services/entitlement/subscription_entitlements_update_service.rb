# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlementsUpdateService < BaseService
    include ::Entitlement::Concerns::CreateOrUpdateConcern

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
        if full?
          remove_or_delete_missing_entitlements
        end
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

    def full?
      !partial?
    end

    def subscription_plan_entitlements_as_params
      @subscription_plan_entitlements_as_params ||= (subscription.plan.parent || subscription.plan)
        .entitlements
        .includes(:feature, values: :privilege)
        .map { |entitlement| [entitlement.feature.code, entitlement.values.map { |v| [v.privilege.code, v.value] }.to_h] }
        .to_h
    end

    def remove_or_delete_missing_entitlements
      # TODO: Make dedicated query?
      missing_codes = (SubscriptionEntitlement.for_subscription(subscription).map(&:code) - entitlements_params.keys).uniq

      # If the feature was added as a subscription override, delete it
      sub_entitlements = subscription.entitlements.joins(:feature).where(feature: {code: missing_codes})
      EntitlementValue.where(entitlement: sub_entitlements).discard_all!
      sub_entitlements.discard_all!

      # If the feature is from the plan, create a SubscriptionFeatureRemoval
      plan_entitlements = subscription.plan.entitlements.joins(:feature).where(feature: {code: missing_codes})
      plan_entitlements.each do |entitlement|
        SubscriptionFeatureRemoval.create!(
          organization: subscription.organization,
          feature: entitlement.feature,
          subscription: subscription
        )
      end
    end

    def delete_missing_entitlement_values(entitlement, privilege_values)
      return if privilege_values.blank?

      entitlement.values.joins(:privilege).where.not(privilege: {code: privilege_values.keys}).discard_all!
    end

    def feature_config_same_as_plan?(feature_code, privilege_values)
      return false if subscription_plan_entitlements_as_params[feature_code].nil?
      return false if privilege_values.keys != subscription_plan_entitlements_as_params[feature_code].keys

      subscription_plan_entitlements_as_params[feature_code].all? do |privilege_code, value|
        if value == "t"
          ["true", true, "t", 1].include? privilege_values[privilege_code]
        elsif value == "f"
          ["false", false, "f", 0].include? privilege_values[privilege_code]
        else
          privilege_values[privilege_code].to_s == value.to_s
        end
      end
    end

    def update_entitlements
      return if entitlements_params.blank?

      entitlements_params.each do |feature_code, privilege_values|
        feature = organization.features.includes(:privileges).find { it.code == feature_code }

        raise ActiveRecord::RecordNotFound.new("Entitlement::Feature") unless feature

        # if the feature was previously removed, we restore it
        removal = subscription.entitlement_removals.find { it.entitlement_feature_id == feature.id }
        removal&.discard!

        entitlement = subscription.entitlements.includes(:values).find { it.entitlement_feature_id == feature.id }

        # When the params contains the same info as the plan, we delete the override if found or don't create overrides
        if full? && feature_config_same_as_plan?(feature_code, privilege_values)
          if entitlement
            entitlement.values.discard_all!
            entitlement.discard!
          end

          next
        end

        if entitlement.nil?
          entitlement = Entitlement.create!(
            organization: organization,
            feature: feature,
            subscription_id: subscription.id
          )
        elsif full?
          delete_missing_entitlement_values(entitlement, privilege_values)
        end

        update_entitlement_values(entitlement, feature, privilege_values)
      end
    end

    def create_entitlement_values(entitlement, feature, privilege_values)
      privilege_values.each do |privilege_code, value|
        privilege = find_privilege!(feature.privileges, privilege_code)

        create_entitlement_value(entitlement, privilege, value)
      end
    end

    def update_entitlement_values(entitlement, feature, privilege_values)
      return if privilege_values.blank?

      privilege_values.each do |privilege_code, value|
        privilege = find_privilege!(feature.privileges, privilege_code)

        entitlement_value = entitlement.values.find { it.entitlement_privilege_id == privilege.id }

        if entitlement_value
          entitlement_value.update!(value: validate_value(value, privilege))
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
        value: validate_value(value, privilege)
      )
    end

    def find_privilege!(privileges, privilege_code)
      privilege = privileges.find { it.code == privilege_code }
      privilege || raise(ActiveRecord::RecordNotFound.new("Entitlement::Privilege"))
    end
  end
end
