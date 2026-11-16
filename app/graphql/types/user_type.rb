# frozen_string_literal: true

module Types
  class UserType < Types::BaseObject
    field :id, ID, null: false

    field :cs_admin, Boolean, null: false
    field :email, String
    field :premium, Boolean, null: false

    field :memberships, [Types::MembershipType], null: false
    field :needs_organization, Boolean, null: false, description: "True for a self-serve user who must create an organization (signup Step 3)"
    # TODO: keeping organization for backwards compatibility, remove once the frontend is updated
    field :organizations, [Types::Organizations::OrganizationType], null: false

    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def memberships
      ordered_active_memberships
    end

    def organizations
      ordered_active_memberships.map(&:organization)
    end

    def premium
      License.premium?
    end

    # Only self-serve users load their memberships, in one batch, so member lists cause no N+1.
    def needs_organization
      dataloader.with(Sources::ActiveRecordAssociation, :memberships).load(object) if object.self_serve_verified_at?
      object.needs_organization?
    end

    private

    # With self-serve on, oldest membership first and each sandbox right after its production organization: the front
    # falls back to the first membership when no organization is selected yet. Off, the order is unchanged.
    def ordered_active_memberships
      @ordered_active_memberships ||= begin
        relation = object.memberships.active.includes(organization: :integrations)
        Lago::SelfServe.enabled? ? sandbox_after_production(relation) : relation
      end
    end

    # A sandbox whose production membership is not active keeps its own place.
    def sandbox_after_production(relation)
      rows = relation.order(:created_at, :id).to_a
      position = rows.each_with_index.to_h { |membership, index| [membership.organization_id, index] }

      rows.sort_by.with_index do |membership, index|
        production_id = membership.organization.production_organization_id
        [position.fetch(production_id, index), production_id ? 1 : 0, index]
      end
    end
  end
end
