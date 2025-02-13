# frozen_string_literal: true

module Memberships
  class UpdateService < BaseService
    def initialize(membership:, params:)
      @membership = membership
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "membership") unless membership
      return result.not_allowed_failure!(code: "last_admin") if changing_role_of_last_admin?

      membership.update!(
        role: params[:role]
      )

      result.membership = membership
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :membership, :params

    def changing_role_of_last_admin?
      membership.organization.memberships.admin.count == 1 &&
        membership.admin? &&
        params[:role] != "admin"
    end
  end
end
