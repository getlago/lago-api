# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module PreAggregated
        class LatestQuery < Base
          protected

          def aggregation_type
            @aggregation_type ||= 'latest_agg'
          end

          def pre_aggregated_model
            nil
          end

          def clickhouse_aggregation
            nil
          end

          def assign_units(bucket, units)
            bucket[:units] = units
          end

          def enriched_events_query
            query = ::Clickhouse::EventsEnriched
              .where(organization_id: organization.id)
              .where(external_subscription_id: subscription.external_id)
              .where(charge_id: charge_ids)
              .where(timestamp: from_datetime...to_datetime) # TODO: check for miliseconds
              .select(
                [
                  'DISTINCT ON (events_enriched.charge_id, events_enriched.grouped_by, events_enriched.filters) events_enriched.charge_id',
                  'events_enriched.grouped_by',
                  'events_enriched.filters',
                  'events_enriched.timestamp',
                  "toDecimal128(events_enriched.value, #{ClickhouseStore::DECIMAL_SCALE}) as units"
                ].join(', ')
              )
              .order('events_enriched.charge_id, events_enriched.grouped_by, events_enriched.filters, events_enriched.timestamp DESC')

            ::Clickhouse::EventsEnriched.connection.select_all(query.to_sql)
          end
        end
      end
    end
  end
end
