# frozen_string_literal: true

module V2
  class SecurityLogSerializer < ModelSerializer
    timestamps :logged_at, :created_at

    def serialize
      {
        log_id: model.log_id,
        log_type: model.log_type,
        log_event: model.log_event,
        user_email: model.user&.email,
        # resources and device_info are deep-parsed in Clickhouse::SecurityLog
        # (JSON-encoded map values, with the raw value kept on JSON::ParserError).
        resources: model.resources,
        device_info: model.device_info
      }
    end
  end
end
