# frozen_string_literal: true

module Types
  module Organizations
    # Shown only to an active member, as the customer portal and the public invite query reach this type. Login and
    # signup payloads have no session and answer null: clients read it from currentUser, which stays open while the
    # organization waits for a payment method (RequiredOrganization refuses currentOrganization then).
    module ActivationFields
      extend ActiveSupport::Concern
      include ViewerMembership

      included do
        field :activation_status, Types::Organizations::ActivationStatusEnum
      end

      def activation_status
        object.effective_activation_status if viewer_active_member?(object.id)
      end
    end
  end
end
