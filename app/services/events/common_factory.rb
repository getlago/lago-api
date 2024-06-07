# frozen_string_literal: true

module Events
  class CommonFactory
    def self.new_instance(source:)
      case source.class.name
      when 'Events::Common'
        source
      when 'Hash'
        Events::Common.new(
          organization_id: source['organization_id'],
          transaction_id: source['transaction_id'],
          external_subscription_id: source['external_subscription_id'],
          timestamp: Time.zone.at(source['timestamp'].to_f),
          code: source['code'],
          properties: source['properties']
        )
      when 'Event'
        Events::Common.new(
          id: source.id,
          organization_id: source.organization_id,
          transaction_id: source.transaction_id,
          external_subscription_id: source.external_subscription_id,
          timestamp: source.timestamp,
          code: source.code,
          properties: source.properties
        )
      when 'Clickhouse::EventsRaw'
        Events::Common.new(
          organization_id: source.organization_id,
          transaction_id: source.transaction_id,
          external_subscription_id: source.external_subscription_id,
          timestamp: source.timestamp,
          code: source.code,
          properties: source.properties
        )
      end
    end
  end
end
