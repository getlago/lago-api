# frozen_string_literal: true

module V2
  class OrganizationSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        slug: model.slug,
        email: model.email,
        events_store: model.events_store,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at)
      }
    end
  end
end
