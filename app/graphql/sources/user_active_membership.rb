# frozen_string_literal: true

module Sources
  # Batches whether a user is an active member of each organization, in the order of the ids.
  #
  # Usage in GraphQL types:
  #   dataloader.with(Sources::UserActiveMembership, user.id).load(organization.id)
  class UserActiveMembership < GraphQL::Dataloader::Source
    def initialize(user_id)
      @user_id = user_id
    end

    def fetch(organization_ids)
      member_of = Membership.active.where(user_id: @user_id, organization_id: organization_ids)
        .pluck(:organization_id).to_set

      organization_ids.map { member_of.include?(it) }
    end
  end
end
