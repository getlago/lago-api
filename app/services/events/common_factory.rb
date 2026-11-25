# frozen_string_literal: true

module Events
  class CommonFactory
    def self.new_instance(source:)
      case source.class.name
      when "Events::Common"
        source
      when "Hash"
        event = Events::Common.new(
          id: source["id"],
          organization_id: source["organization_id"],
          transaction_id: source["transaction_id"],
          external_subscription_id: source["external_subscription_id"],
          timestamp: Events::Common.timestamp_from_source(source),
          code: source["code"],
          properties: source["properties"],
          created_at: created_at_from_source(source)
        )

        if source["precise_total_amount_cents"].present?
          event.precise_total_amount_cents = BigDecimal(source["precise_total_amount_cents"].to_s)
        end

        event
      when "Event"
        Events::Common.new(
          id: source.id,
          organization_id: source.organization_id,
          transaction_id: source.transaction_id,
          external_subscription_id: source.external_subscription_id,
          timestamp: source.timestamp,
          code: source.code,
          properties: source.properties,
          precise_total_amount_cents: source.precise_total_amount_cents,
          created_at: source.created_at
        )
      # Events read back from ClickHouse, without an id, as for an event the processor forwards.
      when "Clickhouse::EventsEnriched"
        Events::Common.new(
          id: nil,
          organization_id: source.organization_id,
          transaction_id: source.transaction_id,
          external_subscription_id: source.external_subscription_id,
          timestamp: source.timestamp,
          code: source.code,
          properties: source.properties,
          precise_total_amount_cents: source.precise_total_amount_cents
        )
      # A product event is keyed by contract, which the pay in advance path reads as external_subscription_id.
      when "Clickhouse::ProductEventsEnriched"
        Events::Common.new(
          id: nil,
          organization_id: source.organization_id,
          transaction_id: source.transaction_id,
          external_subscription_id: source.external_contract_id,
          timestamp: source.timestamp,
          code: source.code,
          properties: source.properties,
          precise_total_amount_cents: source.precise_total_amount_cents
        )
      when "Clickhouse::EventsRaw"
        Events::Common.new(
          id: nil,
          organization_id: source.organization_id,
          transaction_id: source.transaction_id,
          external_subscription_id: source.external_subscription_id,
          timestamp: source.timestamp,
          code: source.code,
          properties: source.properties,
          precise_total_amount_cents: source.precise_total_amount_cents,
          created_at: source.created_at
        )
      end
    end

    def self.created_at_from_source(source)
      value = source["created_at"]
      return if value.nil?

      Time.zone.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
