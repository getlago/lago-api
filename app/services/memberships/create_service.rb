# frozen_string_literal: true

module Memberships
  class CreateService < ::BaseService
    Result = BaseResult[:membership]

    def initialize(user:, organization:)
      @user = user
      @organization = organization

      super
    end

    def call
      return result.not_found_failure!(resource: "user") unless user
      return result.not_found_failure!(resource: "organization") unless organization

      ActiveRecord::Base.transaction do
        Organizations::SandboxLockService.call!(organization:)
        result.membership = Membership.create!(user:, organization:)
        Memberships::SyncSandboxService.call!(organization:, user:)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, "index_memberships_on_user_id_and_organization_id" => :user_id)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :user, :organization
  end
end
