# frozen_string_literal: true

module V2
  class OrganizationSerializer < ModelSerializer
    timestamps :created_at, :updated_at

    def serialize
      {
        lago_id: model.id,
        name: model.name,
        slug: model.slug,
        email: model.email,
        events_store: model.events_store
      }
    end
  end
end
