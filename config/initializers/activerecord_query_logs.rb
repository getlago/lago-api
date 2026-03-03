# frozen_string_literal: true

if ENV["LAGO_ENABLE_QUERY_LOG_TAGGING"] == "true" &&
    ENV["DATABASE_PREPARED_STATEMENTS"] == "true"
  raise "Query log tagging is incompatible with prepared statements. " \
        "Set DATABASE_PREPARED_STATEMENTS=false or disable query log tagging."
end

if ENV["LAGO_ENABLE_QUERY_LOG_TAGGING"] == "true"
  Rails.application.configure do
    config.active_record.query_log_tags_enabled = true
    config.active_record.query_log_tags = %i[application controller action source_location]
  end
end
