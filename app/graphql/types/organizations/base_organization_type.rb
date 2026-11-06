# frozen_string_literal: true

module Types
  module Organizations
    class BaseOrganizationType < BaseObject
      def billing_configuration
        {
          id: "#{object&.id}-c0nf", # Each nested object needs ID so that appollo cache system can work properly
          invoice_footer: object&.invoice_footer,
          invoice_grace_period: object&.invoice_grace_period,
          document_locale: object&.document_locale,
          eu_tax_management: object&.eu_tax_management
        }
      end

      def production_organization
        linked_organization(:production_organization) if object.sandbox?
      end

      def sandbox_organization
        linked_organization(:sandbox_organization) if object.production?
      end

      private

      # These types are reachable from the public invite query and from other members' memberships, so a linked
      # organization is shown only to a viewer who is an active member of it.
      def linked_organization(association)
        viewer = context[:current_user]
        return if viewer.nil?

        linked = dataloader.with(Sources::ActiveRecordAssociation, association).load(object)
        linked if linked && dataloader.with(Sources::UserActiveMembership, viewer.id).load(linked.id)
      end
    end
  end
end
