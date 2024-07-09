# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module PreAggregated
        class Base
          def initialize(subscription:, boundaries:)
            @subscription = subscription
            @boundaries = boundaries
          end

          def call
            result.charge_results = {}

            append_to_result(pre_aggregated_query, initial_result: result.charge_results)
            append_to_result(enriched_events_query, initial_result: result.charge_results)

            result
          end

          protected

          attr_reader :subscription, :boundaries

          delegate :organization, to: :subscription

          def aggregation_type
            # NOTE: override in subclasses
            raise NotImplementedError
          end

          def pre_aggregated_model
            # NOTE: override in subclasses
            raise NotImplementedError
          end

          def clickhouse_aggregation
            # NOTE: override in subclasses
            raise NotImplementedError
          end

          def from_datetime
            @from_datetime ||= boundaries[:from_datetime]
          end

          def to_datetime
            @to_datetime ||= boundaries[:to_datetime]
          end

          def check_before_boundaries?
            from_datetime.beginning_of_hour != from_datetime
          end

          def check_after_boundaries?
            to_datetime.end_of_hour != to_datetime # TODO: check for miliseconds
          end

          def charge_ids
            @charge_ids ||= subscription.plan.charges.joins(:billable_metric)
              .merge(BillableMetric.where(aggregation_type: aggregation_type))
              .pluck(:id)
          end

          def pre_aggregated_counts_query
            sql = pre_aggregated_model.where(organization_id: organization.id)
              .where(external_subscription_id: subscription.external_id)
              .where(charge_id: charge_ids)
              .where(timestamp: from_datetime...)
              .where(timestamp: ..to_datetime.beginning_of_hour)
              .group(:charge_id, :grouped_by, :filters)
              .select("#{clickhouse_aggregation}(value) as units, charge_id, grouped_by, filters")
              .to_sql

            pre_aggregated_model.connection.select_all(sql)
          end

          def enriched_events_query
            return [] if !check_before_boundaries? && !check_after_to_boundaries?

            base_scope = Clickhouse::EventsEnriched
              .where(organization_id: organization.id)
              .where(external_subscription_id: subscription.external_id)
              .where(charge_id: charge_ids)
              .group(:charge_id, :grouped_by, :filters)
              .select("#{clickhouse_aggregation}(toDecimal128(value, #{ClickhouseStore::DECIMAL_SCALE})) as units, charge_id, grouped_by, filters")

            if check_before_boundaries?
              base_scope = base_scope.where(timestamp: from_datetime...from_datetime.end_of_hour)
            end

            if check_after_boundaries?
              base_scope = base_scope.or(Clickhouse::EventsEnriched.where(timestamp: to_datetime.beginning_of_hour...to_datetime.end_of_hour))
            end

            Clickhouse::EventsEnriched.connection.select_all(base_scope.to_sql)
          end

          # NOTE: Build a list of units indexed by charge_id, filters and or grouped_by
          #       The format of the result is similar to the following:
          #
          #         {
          #           "XXXXX" => {
          #             filters: {
          #               '{"key1":"value","key2":"value"}' => {grouped_by: {}, units: 12.0}
          #               '{"key5":"value","key3":"value"}' => {grouped_by: {'{"group_1":"value1","group2":"value2"}' => {units: 12.0}}}, units: 0.0}
          #             }
          #             grouped_by: {'{"group_1":"value1","group2":"value2"}' => {units: 12.0}}}
          #             units: 12.0
          #           }
          #           #...
          #         }
          def append_to_result(grouped_rows, initial_result: {})
            grouped_rows.each_with_object(initial_result) do |row, result|
              charge_id = row['charge_id']
              units = row['units']

              result[charge_id] ||= {filters: {}, grouped_by: {}, units: 0}

              if row['filters'].present?
                result[charge_id][:filters][row['filters'].to_s] ||= {grouped_by: {}, units: 0}

                if row['grouped_by'].present?
                  result[charge_id][:filters][row['filters'].to_s][:grouped_by][row['grouped_by'].to_s] || {units: 0}
                  assign_units(result[charge_id][:filters][row['filters'].to_s][:grouped_by][row['grouped_by'].to_s][:units], units)
                else
                  assign_units(result[charge_id][:filters][row['filters'].to_s][:units], units)
                end
              elsif row['grouped_by'].present?
                result[charge_id][:grouped_by][row['grouped_by'].to_s] ||= {units: 0}
                assign_units(result[charge_id][:grouped_by][row['grouped_by'].to_s], units)
              else
                assign_units(result[charge_id][:units], units)
              end
            end
          end

          def assign_units(bucket, units)
            # NOTE: override in subclasses
            raise NotImplementedError
          end
        end
      end
    end
  end
end
