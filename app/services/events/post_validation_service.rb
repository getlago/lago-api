# frozen_string_literal: true

module Events
  class PostValidationService < BaseService
    def initialize(organization:)
      @organization = organization

      super
    end

    def call
      errors = {
        invalid_code: process_query(invalid_code_query),
        missing_aggregation_property: process_query(missing_aggregation_property_query),
        missing_group_key: process_query(missing_group_key_query),
      }

      if errors[:invalid_code].present? ||
         errors[:missing_aggregation_property].present? ||
         errors[:missing_group_key].present?
        deliver_webhook(errors)
      end

      result.errors = errors
      result
    end

    private

    attr_reader :organization

    def invalid_code_query
      <<-SQL
        SELECT DISTINCT transaction_id
        FROM last_hour_events_mv
        WHERE organization_id = '#{organization.id}'
          AND billable_metric_code IS NULL
      SQL
    end

    def missing_aggregation_property_query
      <<-SQL
        SELECT DISTINCT transaction_id
        FROM last_hour_events_mv
        WHERE organization_id = '#{organization.id}'
          AND (
            (
              field_name_mandatory = 't'
              AND field_value IS NULL
            )
            OR (
              numeric_field_mandatory = 't'
              AND is_numeric_field_value = 'f'
            )
          )
      SQL
    end

    def missing_group_key_query
      <<-SQL
        SELECT DISTINCT transaction_id
        FROM last_hour_events_mv
        WHERE organization_id = '#{organization.id}'
          AND (
            (
              parent_group_mandatory = 't'
              AND has_parent_group_key = 'f'
            )
            OR (
              child_group_mandatory = 't'
              AND has_child_group_key = 'f'
            )
          )
      SQL
    end

    def process_query(sql)
      ApplicationRecord.connection.select_all(sql).rows.map(&:first)
    end

    def deliver_webhook(errors)
      SendWebhookJob.perform_later('events.errors', organization, errors:)
    end
  end
end
