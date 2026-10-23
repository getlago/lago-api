# frozen_string_literal: true

module V2
  class SecurityLogSerializer < ModelSerializer
    def serialize
      {
        log_id: model.log_id,
        log_type: model.log_type,
        log_event: model.log_event,
        user_email: model.user&.email,
        logged_at: model.logged_at.iso8601,
        created_at: model.created_at.iso8601,
        # resources and device_info are deep-parsed in Clickhouse::SecurityLog
        # (JSON-encoded map values, with the raw value kept on JSON::ParserError).
        resources: model.resources,
        device_info: model.device_info
      }
    end
  end
end
