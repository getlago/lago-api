# frozen_string_literal: true

module Memberships
  class CreateFromInviteService < ::BaseService
    Result = BaseResult[:membership]

    def initialize(invite:, user:)
      @invite = invite
      @user = user

      super
    end

    # NOTE: Callers rescue ActiveRecord::RecordInvalid. They run this service in their own
    #       transaction.
    def call
      result.membership = Membership.create!(user:, organization: invite.organization)

      invite.roles.each do |role_code|
        role = Role.with_code(role_code).with_organization(invite.organization_id).first!

        MembershipRole.create!(
          organization: invite.organization,
          membership: result.membership,
          role:
        )
      end

      result
    end

    private

    attr_reader :invite, :user
  end
end
