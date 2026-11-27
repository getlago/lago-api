# frozen_string_literal: true

module BillingEngineMigrations
  # The migration is read again when the job runs: events enqueued before a pause or a switch to
  # the raw topic are left to the path that copies them now, so no event is copied twice.
  class CopyApiEventsService < BaseService
    Result = BaseResult[:copied_count, :unmapped_count]

    def initialize(organization_id:, events_json:)
      @organization_id = organization_id
      @events_json = events_json
      super
    end

    def call
      migration = Lookup.for_source(organization_id)
      return result unless migration&.events_copy_source == BillingEngineMigration::EVENTS_COPY_SOURCES[:api]

      copy_result = CopyEventsService.call!(migration:, events: JSON.parse(events_json).map { build_event(it) })
      result.copied_count = copy_result.copied_count
      result.unmapped_count = copy_result.unmapped_count
      result
    end

    private

    attr_reader :organization_id, :events_json

    def build_event(attributes)
      CopyEventsService::Event.new(**attributes.symbolize_keys.merge(timestamp: Time.zone.at(attributes["timestamp"])))
    end
  end
end
