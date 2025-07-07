# frozen_string_literal: true

module Entitlement
  class FeatureFullUpdateService < FeatureBaseUpdateService
    def call
      handle_validation_and_webhooks do
        ActiveRecord::Base.transaction do
          update_feature_attributes
          delete_missing_privileges
          update_privileges if params[:privileges].present?

          feature.save!
        end
      end
    end

    private

    def delete_missing_privileges
      # Find privileges that are in the database but not in the params
      # Delete all EntitlementValues associated with those privileges
      # Then delete the privileges themselves
      missing_privilege_codes = feature.privileges.pluck(:code) - (params[:privileges] || {}).keys
      EntitlementValue.where(privilege: feature.privileges.where(code: missing_privilege_codes)).discard_all!
      feature.privileges.where(code: missing_privilege_codes).discard_all!
      missing_privilege_codes.each do |code|
        privilege = feature.privileges.find { it[:code] == code }
        next unless privilege
        privilege.discard!
      end
    end
  end
end
