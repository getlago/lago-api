# frozen_string_literal: true

WEBHOOK_EVENT_TYPES = YAML.load_file(Rails.root.join("config/webhook_event_types.yml")).deep_symbolize_keys
