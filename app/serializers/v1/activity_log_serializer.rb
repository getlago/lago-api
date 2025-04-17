# frozen_string_literal: true

module V1
  class ActivityLogSerializer < ModelSerializer
    def serialize
      {
        lago_user_id: model.user_id,
        resource_id: model.resource_id,
        resource_type: model.resource_type,
        activity_id: model.activity_id,
        activity_type: model.activity_type,
        activity_source: model.activity_source,
        external_customer_id: model.external_customer_id,
        external_subscription_id: model.external_subscription_id,
        logged_at: model.logged_at.iso8601,
        created_at: model.created_at.iso8601,
        activity_object: model.activity_object,
        activity_object_changes: model.activity_object_changes
      }
    end
  end
end
