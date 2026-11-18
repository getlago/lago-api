# frozen_string_literal: true

module Types
  module Organizations
    # The activation status on the shared organization type, which the customer portal and the public invite query
    # also reach: it is shown only to a viewer who is an active member of the organization.
    module ActivationFields
      extend ActiveSupport::Concern

      included do
        field :activation_status, Types::Organizations::ActivationStatusEnum
      end

      def activation_status
        viewer = context[:current_user]
        return if viewer.nil?

        object.activation_status if dataloader.with(Sources::UserActiveMembership, viewer.id).load(object.id)
      end
    end
  end
end
