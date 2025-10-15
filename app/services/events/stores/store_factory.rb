# frozen_string_literal: true

module Events
  module Stores
    class StoreFactory
      class << self
        def supports_clickhouse?
          ENV["LAGO_CLICKHOUSE_ENABLED"].present?
        end
      end

      def self.store_class(organization:, current_usage: false)
        event_store = Events::Stores::PostgresStore

        if supports_clickhouse? && organization.clickhouse_events_store?
          event_store = if current_usage && organization.clickhouse_live_aggregation_enabled?
            Events::Stores::AggregatedClickhouseStore
          else
            Events::Stores::ClickhouseStore
          end
        end

        event_store
      end

      def self.new_instance(organization:, current_usage: false, **kwargs)
        store_class(organization: organization, current_usage: current_usage).new(**kwargs)
      end
    end
  end
end
