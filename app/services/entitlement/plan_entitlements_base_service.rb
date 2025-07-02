# frozen_string_literal: true

module Entitlement
  class PlanEntitlementsBaseService < BaseService
    def initialize(organization:, plan:, entitlements_params:)
      @organization = organization
      @plan = plan
      @entitlements_params = entitlements_params
      super
    end

    protected

    attr_reader :organization, :plan, :entitlements_params

    def create_entitlement_values(entitlement, feature, privilege_values)
      privilege_values.each do |privilege_code, value|
        privilege = feature.privileges.find_by!(code: privilege_code)

        EntitlementValue.create!(
          organization: plan.organization,
          entitlement: entitlement,
          privilege: privilege,
          value: validate_and_stringify(value, privilege)
        )
      end
    end

    def update_entitlement_values(entitlement, feature, privilege_values)
      privilege_values.each do |privilege_code, value|
        privilege = feature.privileges.find { it.code == privilege_code }

        raise ActiveRecord::RecordNotFound.new("Entitlement::Privilege") unless privilege

        entitlement_value = entitlement.values.find { it.entitlement_privilege_id == privilege.id }

        if entitlement_value
          # Update existing value
          entitlement_value.update!(
            value: validate_and_stringify(value, privilege)
          )
        else
          # Create new value
          EntitlementValue.create!(
            organization: plan.organization,
            entitlement: entitlement,
            privilege: privilege,
            value: validate_and_stringify(value, privilege)
          )
        end
      end
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

    def handle_validation_errors
      yield
    rescue ValidationFailure => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(Entitlement::EntitlementValue)
        errors = e.record.errors.messages.transform_keys { |key| :"entitlement_value.#{key}" }
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
  end
end
