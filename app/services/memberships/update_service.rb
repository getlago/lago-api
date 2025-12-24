# frozen_string_literal: true

module Memberships
  class UpdateService < BaseService
    Result = BaseResult[:membership]

    def initialize(membership:, params:)
      @membership = membership
      @params = params

      super
    end

    def call
      ActiveRecord::Base.transaction do
        return result.not_found_failure!(resource: "membership") unless membership
        return result.not_found_failure!(resource: "role") if new_roles.blank?
        return result.not_allowed_failure!(code: "last_admin") if last_admin_demotion?

        roles_to_remove = old_roles - new_roles
        (new_roles - old_roles).each { |role| MembershipRole.create!(organization:, membership:, role:) }
        MembershipRole.where(membership:, role: roles_to_remove).discard_all! if roles_to_remove.present?
      end

      result.membership = membership.reload
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :membership, :params

    def organization
      @organization ||= membership.organization
    end

    def new_roles
      @new_roles ||= Role.with_code(*params[:roles]).with_organization(membership.organization_id)
    end

    def old_roles
      @old_roles ||= membership.roles
    end

    def last_admin_demotion?
      membership.admin? && new_roles.none?(&:admin?) && organization.admin_membership_roles.count == 1
    end
  end
end
