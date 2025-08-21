# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlementCreateOrUpdateService < BaseService
    include ::Entitlement::Concerns::CreateOrUpdateConcern

    Result = BaseResult[:entitlement]

    def initialize(subscription:, feature_code:, privilege_params:)
      @subscription = subscription
      @feature_code = feature_code
      @privilege_params = privilege_params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription }
    )

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "subscription") unless subscription
      return result.not_found_failure!(resource: "feature") unless feature

      ActiveRecord::Base.transaction do
        process_single_entitlement
      end

      result.entitlement = SubscriptionEntitlement.for_subscription(subscription).find { it.code == feature_code }

      result
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

    attr_reader :subscription, :feature_code, :privilege_params
    delegate :organization, to: :subscription

    def feature
      @feature ||= organization.features.includes(:privileges).find_by(code: feature_code)
    end

    def plan
      @plan ||= subscription.plan.parent || subscription.plan
    end

    def process_single_entitlement
      plan_entitlement = plan.entitlements.includes(values: :privilege).find_by(feature: feature)
      sub_entitlement = subscription.entitlements.includes(values: :privilege).find_by(feature: feature)
      # TODO: add .or.where(privilege: feature.privileges)
      removals = SubscriptionFeatureRemoval.where(subscription: subscription, feature: feature).to_a

      if plan_entitlement.nil? && sub_entitlement.nil?
        feature_removal = removals.find { it.entitlement_feature_id == feature.id }
        feature_removal&.discard!
        create_entitlement_and_values_for_subscription
      elsif plan_entitlement && privilege_params_same_as_plan?(plan_entitlement)
        # Restore the plan default by removing all overrides
        sub_entitlement&.values&.update_all(deleted_at: Time.zone.now)
        sub_entitlement&.discard!
        feature_removal = removals.find { it.entitlement_feature_id == feature.id }
        feature_removal&.discard!
      else
        feature_removal = removals.find { it.entitlement_feature_id == feature.id }
        feature_removal&.discard!
        sub_entitlement ||= create_entitlement_for_subscription
        update_values_for_subscription(plan_entitlement, sub_entitlement)
      end
    end

    def create_entitlement_for_subscription
      Entitlement.create!(
        organization: organization,
        subscription: subscription,
        feature: feature
      )
    end

    def create_entitlement_and_values_for_subscription
      entitlement = create_entitlement_for_subscription

      privilege_params.each do |privilege_code, value|
        privilege = find_privilege!(feature.privileges, privilege_code)

        create_entitlement_value(entitlement, privilege, value)
      end

      entitlement
    end

    def update_values_for_subscription(plan_entitlement, sub_entitlement)
      # TODO: REMOVE MISSING VALUES when possible

      privilege_params.each do |privilege_code, value|
        privilege = find_privilege!(feature.privileges, privilege_code)

        plan_val = plan_entitlement.values.find { it.privilege.code == privilege_code }
        sub_val = sub_entitlement.values.find { it.privilege.code == privilege_code }

        # TODO: FIX VALUE COMPARISON
        if plan_val && value == plan_val.value
          sub_val&.discard!
        elsif sub_val.nil?
          # TODO: REMOVE PRIVILEGE REMOVAL

          create_entitlement_value(sub_entitlement, privilege, value)
        elsif sub_val && value != sub_val.value
          sub_val.update!(value: validate_value(value, privilege))
        end
      end
    end

    def create_entitlement_value(entitlement, privilege, value)
      entitlement.values.create!(
        organization: organization,
        privilege: privilege,
        value: validate_value(value, privilege)
      )
    end

    def find_privilege!(privileges, privilege_code)
      privilege = privileges.find { it.code == privilege_code }
      privilege || raise(ActiveRecord::RecordNotFound.new("Entitlement::Privilege"))
    end

    def privilege_params_same_as_plan?(plan_entitlement)
      # TODO: Fix this to ensure "9" == 9 (see )
      #     See: SubscriptionEntitlementsUpdateService.feature_config_same_as_plan?
      plan_entitlement.values.map do |v|
        [v.privilege.code, v.value]
      end.to_h.eql? privilege_params
    end

    # def subscription_plan_entitlements_as_params
    #   @subscription_plan_entitlements_as_params ||= (subscription.plan.parent || subscription.plan)
    #     .entitlements
    #     .includes(:feature, values: :privilege)
    #     .map { |entitlement| [entitlement.feature.code, entitlement.values.map { |v| [v.privilege.code, v.value] }.to_h] }
    #     .to_h
    # end
  end
end
