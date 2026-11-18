# frozen_string_literal: true

module Entitlement
  # Sets the overrides of one feature on a subscription (the override owner).
  class SubscriptionEntitlementCoreUpdateService < BaseService
    include ::Entitlement::Concerns::CreateOrUpdateConcern
    include ::Entitlement::Concerns::OverrideOwnerConcern

    Result = BaseResult

    # Callers pass `subscription:`, or `owner:` for any override owner.
    def initialize(plan:, feature:, plan_entitlement:, sub_entitlement:, privilege_params:, partial:, subscription: nil, owner: subscription)
      @owner = owner
      @plan = plan
      @feature = feature
      @plan_entitlement = plan_entitlement
      @sub_entitlement = sub_entitlement
      @privilege_params = privilege_params.to_h.with_indifferent_access
      @partial = partial
      super
    end

    # This inner service is used to update a single entitlement
    # It intentionally doesn't add any activity log entries, doesn't return any data, doesn't send any webhooks
    # The outer services will handle that
    def call
      return result.not_found_failure!(resource: "feature") unless feature

      ActiveRecord::Base.transaction do
        process_single_entitlement
      end

      result
    end

    private

    attr_reader :owner, :plan, :feature, :plan_entitlement, :sub_entitlement, :privilege_params, :partial
    delegate :organization, to: :owner
    alias_method :partial?, :partial

    def full?
      !partial?
    end

    def process_single_entitlement
      if plan_entitlement.nil? && sub_entitlement.nil?
        owner.entitlement_removals.where(feature:).update_all(discarded_columns) # rubocop:disable Rails/SkipsModelValidations
        create_entitlement_and_values_for_owner
      elsif plan_entitlement && privilege_params_same_as_plan?(plan_entitlement)
        # Restore the plan default by removing all overrides
        sub_entitlement&.values&.update_all(discarded_columns) # rubocop:disable Rails/SkipsModelValidations
        sub_entitlement&.discard!
        SubscriptionFeatureRemoval.where(owner_attributes).merge(
          SubscriptionFeatureRemoval.where(feature:)
            .or(SubscriptionFeatureRemoval.where(privilege: feature.privileges))
        ).update_all(discarded_columns) # rubocop:disable Rails/SkipsModelValidations
      else
        owner.entitlement_removals.where(feature:).update_all(discarded_columns) # rubocop:disable Rails/SkipsModelValidations

        sub_entitlement = self.sub_entitlement || create_entitlement_for_owner
        remove_missing_entitlement_values(plan_entitlement, sub_entitlement) if full?
        update_values_for_owner(plan_entitlement, sub_entitlement)
      end
    end

    def create_entitlement_for_owner
      Entitlement.create!(
        organization: organization,
        feature: feature,
        **owner_attributes
      )
    end

    def create_entitlement_and_values_for_owner
      entitlement = create_entitlement_for_owner

      privilege_params.each do |privilege_code, value|
        privilege = find_privilege!(privilege_code)

        create_entitlement_value(entitlement, privilege, value)
      end

      entitlement
    end

    def remove_missing_entitlement_values(plan_entitlement, sub_entitlement)
      plan_privilege_codes = plan_entitlement&.values&.map { it.privilege.code }
      sub_privilege_codes = sub_entitlement&.values&.map { it.privilege.code }
      privilege_codes_to_remove = ((plan_privilege_codes.to_a + sub_privilege_codes.to_a) - privilege_params.keys).uniq

      privilege_codes_to_remove.each do |privilege_code|
        sub_val = sub_entitlement&.values&.find { it.privilege.code == privilege_code }
        sub_val&.discard!
        plan_val = plan_entitlement&.values&.find { it.privilege.code == privilege_code }

        if plan_val && !SubscriptionFeatureRemoval.where(organization:, privilege: plan_val.privilege, **owner_attributes).exists?
          SubscriptionFeatureRemoval.create!(organization:, privilege: plan_val.privilege, **owner_attributes)
        end
      end
    end

    def update_values_for_owner(plan_entitlement, sub_entitlement)
      privilege_params.each do |privilege_code, value|
        privilege = find_privilege!(privilege_code)

        plan_val = plan_entitlement&.values&.find { it.privilege.code == privilege_code }
        sub_val = sub_entitlement&.values&.find { it.privilege.code == privilege_code }

        if plan_val && value_is_the_same?(privilege.value_type, value, plan_val.value)
          sub_val&.discard!
          delete_all_privilege_entitlement_removals(privilege)
        elsif sub_val.nil?
          delete_all_privilege_entitlement_removals(privilege)

          create_entitlement_value(sub_entitlement, privilege, value)
        elsif sub_val && !value_is_the_same?(privilege.value_type, value, sub_val.value)
          sub_val.update!(value: validate_value(value, privilege))
        end
      end
    end

    def value_is_the_same?(type, value1, value2)
      Utils::Entitlement.same_value?(type, value1, value2)
    end

    def delete_all_privilege_entitlement_removals(privilege)
      owner.entitlement_removals.where(privilege:).update_all(discarded_columns) # rubocop:disable Rails/SkipsModelValidations
    end

    def create_entitlement_value(entitlement, privilege, value)
      entitlement.values.create!(
        organization: organization,
        privilege: privilege,
        value: validate_value(value, privilege)
      )
    end

    def owner_attributes
      {override_owner_key(owner) => owner}
    end

    def find_privilege!(privilege_code)
      feature.privileges.find { it.code == privilege_code } || raise(ActiveRecord::RecordNotFound.new("Entitlement::Privilege"))
    end

    def privilege_params_same_as_plan?(plan_entitlement)
      return false if privilege_params.keys.sort != plan_entitlement.values.map(&:privilege).map(&:code).sort

      plan_entitlement.values.all? do |v|
        value_is_the_same?(v.privilege.value_type, v.value, privilege_params[v.privilege.code])
      end
    end
  end
end
