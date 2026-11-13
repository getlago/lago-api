# frozen_string_literal: true

module Roles
  class CreateService < BaseService
    Result = BaseResult[:role]

    def initialize(organization:, acting_membership:, code:, name:, permissions:, description: nil)
      @organization = organization
      @acting_membership = acting_membership
      @code = code
      @name = name
      @description = description
      @permissions = permissions
      super
    end

    def call
      ActiveRecord::Base.transaction do
        Organizations::SandboxLockService.call!(organization:)
        return result.forbidden_failure! unless License.premium?
        return result.forbidden_failure!(code: "premium_integration_missing") unless organization.custom_roles_enabled?
        return result.forbidden_failure!(code: "cannot_grant_permissions") if granting_permissions_not_held?

        role = organization.roles.create!(
          code:,
          name:,
          description:,
          permissions:
        )
        Roles::SyncSandboxService.call!(role:, actor: acting_membership.user)

        after_commit { register_security_log(role) }
        result.role = role
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :organization, :acting_membership, :code, :name, :description, :permissions

    # A member can only create a role with permissions they hold themselves.
    def granting_permissions_not_held?
      !acting_membership.can_grant_permissions?(Array(permissions))
    end

    def register_security_log(role)
      Utils::SecurityLog.produce(
        organization: organization,
        log_type: "role",
        log_event: "role.created",
        resources: {role_code: role.code, permissions: role.permissions}
      )
    end
  end
end
