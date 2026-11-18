# frozen_string_literal: true

module Types
  module Organizations
    # The activation status on the shared organization type, which the customer portal and the public invite query
    # also reach: it is shown only to a viewer who is an active member of the organization.
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
