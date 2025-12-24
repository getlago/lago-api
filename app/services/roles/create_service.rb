# frozen_string_literal: true

module Roles
  class CreateService < BaseService
    Result = BaseResult[:role]

    def initialize(organization:, name:, permissions:, description: nil)
      @organization = organization
      @name = name
      @description = description
      @permissions = permissions
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.forbidden_failure!(code: "premium_integration_missing") unless organization.custom_roles_enabled?

      role = organization.roles.create!(
        name:,
        description:,
        permissions:
      )

      result.role = role
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :name, :description, :permissions
  end
end
