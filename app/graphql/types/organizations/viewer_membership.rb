# frozen_string_literal: true

module Types
  module Organizations
    # Whether the session's user is an active member of an organization, batched, for the fields of the user-facing
    # organization types that only members may see.
    module ViewerMembership
      extend ActiveSupport::Concern

      private

      def viewer_active_member?(organization_id)
        viewer = context[:current_user]
        viewer.present? && dataloader.with(Sources::UserActiveMembership, viewer.id).load(organization_id)
      end
    end
  end
end
