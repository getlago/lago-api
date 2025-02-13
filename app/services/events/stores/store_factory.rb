# frozen_string_literal: true

module Events
  module Stores
    class StoreFactory
      class << self
        def supports_clickhouse?
          ENV["LAGO_CLICKHOUSE_ENABLED"].present?
        end
      end

      def self.store_class(organization:)
        event_store = Events::Stores::PostgresStore

        if supports_clickhouse? && organization.clickhouse_events_store?
          event_store = Events::Stores::ClickhouseStore
        end

        event_store
      end
    end
  end
end
