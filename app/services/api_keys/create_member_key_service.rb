# frozen_string_literal: true

module ApiKeys
  # Mints the key the AI agent calls the API with, carrying the permissions of the member it acts
  # for. It lives for one turn of the conversation: the caller destroys it once the turn ends, and
  # it expires on its own if that never happens.
  class CreateMemberKeyService < BaseService
    Result = BaseResult[:api_key]

    EXPIRATION = 1.hour

    def initialize(membership:)
      @membership = membership
      super
    end

    def call
      result.api_key = membership.organization.member_api_keys.create!(
        membership:,
        name: "AI agent",
        expires_at: EXPIRATION.from_now,
        permissions: MemberPermissions.for(membership)
      )
      result
    end

    private

    attr_reader :membership
  end
end
