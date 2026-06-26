# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Memberships
  class CreateService < ::BaseService
    def initialize(user:, organization:)
      @user = user
      @organization = organization

      super
    end

    def call
      return result.not_found_failure!(resource: "user") unless user
      return result.not_found_failure!(resource: "organization") unless organization

      result.membership = Membership.create!(user:, organization:)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :user, :organization
  end
end
