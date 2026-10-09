# frozen_string_literal: true

module UsageAttributionValues
  # Lazily creates the attribution values of ingested events (the account tree nodes: users, teams,
  # API keys...), outside of the ingestion request.
  #
  # Every event of a high volume customer carries the same few values, so each combination of a
  # subscription and its labels is only handed to the job once per SEEN_TTL, across all the API
  # processes. The job runs once per request, with the combinations seen for the first time.
  #
  # It runs within the ingestion request, so the common case costs two cache calls and no SQL query,
  # whatever the number of events: the types are cached for TYPES_TTL, and the combinations of a
  # request are checked at once. Only combinations seen for the first time cost a write each.
  #
  # Attribution values are best effort: the events are already produced, so a failure is reported
  # and never rejects them. A combination lost that way is tracked again once SEEN_TTL expires.
  class TrackEventsService < BaseService
    SEEN_TTL = 1.hour
    TYPES_TTL = 15.seconds
    KEY_SEPARATOR = "\u001F"

    # What the labels need of a type.
    AttributionType = Data.define(:code, :attribution_keys)

    Result = BaseResult

    def initialize(organization:, events:)
      @organization = organization
      @events = Array.wrap(events)

      super
    end

    def call
      return result unless organization.account_tree_enabled?

      attribution_types = cached_attribution_types
      return result if attribution_types.empty?

      entries = first_seen_entries(attribution_types)
      if entries.any?
        UsageAttributionValues::TrackJob.perform_later(organization, entries)
      end

      result
    rescue => e
      Rails.logger.error("[usage_attribution_values] tracking failed organization_id=#{organization.id}: #{e.class} #{e.message}")
      Sentry.capture_exception(e, extra: {organization_id: organization.id})

      result
    end

    private

    attr_reader :organization, :events

    def cached_attribution_types
      types = Rails.cache.fetch("usage_attribution_values/types/#{organization.id}", expires_in: TYPES_TTL) do
        UsageAttributionType.where(organization_id: organization.id).pluck(:code, :attribution_keys)
      end

      types.map { |code, attribution_keys| AttributionType.new(code:, attribution_keys:) }
    end

    def first_seen_entries(attribution_types)
      combinations = latest_combinations(attribution_types)
      return [] if combinations.empty?

      already_seen = Rails.cache.read_multi(*combinations.pluck(:key)).keys.to_set

      combinations
        .select { |combination| !already_seen.include?(combination[:key]) && mark_seen(combination[:key]) }
        .pluck(:entry)
    end

    def latest_combinations(attribution_types)
      last_seen_at = events.each_with_object({}) do |event, seen|
        labels = UsageAttributions::LabelsService.call(attribution_types:, properties: event.properties).labels
        next if labels.empty?

        key = [event.external_subscription_id, labels.sort.to_h]
        seen[key] = [seen[key], event.timestamp].compact.max
      end

      last_seen_at.map do |(external_subscription_id, labels), seen_at|
        {
          key: seen_key(external_subscription_id, labels),
          entry: {"external_subscription_id" => external_subscription_id, "labels" => labels, "seen_at" => seen_at.iso8601(6)}
        }
      end
    end

    def seen_key(external_subscription_id, labels)
      ["usage_attribution_values/seen", organization.id, external_subscription_id, *labels.flatten].join(KEY_SEPARATOR)
    end

    def mark_seen(key)
      Rails.cache.write(key, true, unless_exist: true, expires_in: SEEN_TTL)
    end
  end
end
