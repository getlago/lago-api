# frozen_string_literal: true

module Events
  module Stores
    class ChargeFiltersScan
      # Keeps the scan rows of a subscription's charge for its events older than a cut, so that a
      # current usage computation reads only the events since that cut instead of every event of
      # the billing period.
      #
      # The cut is a timestamp (the event time, not the ingestion time) lagging the clock and
      # rounded down, so it moves forward in steps and the events of the period are split in two:
      # - the base, `timestamp < cut`, kept here and moved forward one slice at a time;
      # - the tail, `timestamp >= cut`, read on every computation.
      #
      # The rows of the base and the tail combine as the rows of two batches do: a sum of sums, a max
      # of maxes, and the latest value of the tail if it has one, since its events are all more
      # recent than those of the base.
      #
      # Duplicates share their timestamp (it is part of the deduplication key), so an event and
      # the copies replacing it always fall on the same side of the cut, and each read deduplicates
      # its own side with FINAL.
      #
      # The base is only kept while no event older than its cut was ingested after it was read: a
      # late event, or a copy replacing an event of the base, sends the next computation back to a
      # full read. Checking it reads the `enriched_at` of the base's events, which the
      # `idx_enriched_at` skip index narrows to the granules ingested since.
      class IncrementalCache
        CACHE_KEY_VERSION = "2"

        # Events arrive within seconds of their timestamp, so a cut a quarter of an hour behind
        # is rarely crossed by a late event, and the tail stays under half an hour of events.
        CUT_STEP = 15.minutes
        CUT_LAG = 15.minutes

        # An event is stamped with `enriched_at` when its insert begins, not when it becomes
        # readable, so the base only vouches for the events ingested this long before it was read.
        INGESTION_MARGIN = 5.minutes

        # The base is read again in full this often, bounding how long a mistake can last.
        FULL_REFRESH_INTERVAL = 6.hours

        Entry = Data.define(:cut, :watermark, :built_at, :rows)

        # Forgets the bases of the subscription's charge, for changes made to its events without
        # ingesting any (events deleted with their metric, duplicates cleaned up).
        #
        # The generation only has to outlive the bases built before it, which the full refresh
        # rejects past FULL_REFRESH_INTERVAL: kept longer, it would stay in the cache for every
        # subscription of a metric deleted once.
        def self.expire(subscription:, charge:)
          Rails.cache.write(generation_key(subscription.id, charge.id), SecureRandom.hex(8), expires_in: FULL_REFRESH_INTERVAL)
        end

        def self.generation_key(subscription_id, charge_id)
          ["charge-scan-incremental-generation", subscription_id, charge_id].join("/")
        end

        def initialize(subscription:, charge:)
          @subscription = subscription
          @charge = charge
        end

        # The rows of the window, keyed by filter. The block reads the rows of a part of the window,
        # yielded `from_datetime:`, `to_datetime:` and `before:`.
        def rows(store:, from_datetime:, to_datetime:, batch_keys:, group_keys:, &)
          now = Time.current
          cut = cut_at(now)

          unless cut_within?(cut, from_datetime:, to_datetime:)
            return yield(from_datetime:, to_datetime:, before: nil)
          end

          key = cache_key(from_datetime:, to_datetime:, deduplicate: store.deduplicate)
          batch = Digest::SHA256.hexdigest([batch_keys, group_keys].to_json)

          base = base_rows(store:, key:, batch:, now:, cut:, from_datetime:, &)
          tail = yield(from_datetime: cut, to_datetime:, before: nil)

          merge(base, tail)
        end

        private

        attr_reader :subscription, :charge

        def cut_at(time)
          Time.zone.at(((time - CUT_LAG).to_i / CUT_STEP.to_i) * CUT_STEP.to_i)
        end

        # A cut at or before the start of the window leaves nothing to keep, and one at or after
        # its end nothing to read.
        def cut_within?(cut, from_datetime:, to_datetime:)
          (from_datetime.nil? || cut > from_datetime) && (to_datetime.nil? || cut <= to_datetime)
        end

        def base_rows(store:, key:, batch:, now:, cut:, from_datetime:)
          entries = Rails.cache.read(key) || {}
          entry = entries[batch] && load(entries[batch])
          entry = nil unless entry && reusable?(entry, store:, now:, cut:, from_datetime:)

          return entry.rows if entry&.cut == cut

          entry = if entry
            # The base moves forward by the slice between the two cuts. The check that found no
            # late event ran just before, so the new watermark vouches for the older events too.
            Entry.new(
              cut:,
              watermark: now - INGESTION_MARGIN,
              built_at: entry.built_at,
              rows: merge(entry.rows, yield(from_datetime: entry.cut, to_datetime: nil, before: cut))
            )
          else
            Entry.new(
              cut:,
              watermark: now - INGESTION_MARGIN,
              built_at: now,
              rows: yield(from_datetime:, to_datetime: nil, before: cut)
            )
          end

          entries[batch] = dump(entry)
          Rails.cache.write(key, entries, expires_in: FULL_REFRESH_INTERVAL)
          entry.rows
        end

        def reusable?(entry, store:, now:, cut:, from_datetime:)
          entry.built_at > now - FULL_REFRESH_INTERVAL &&
            entry.cut <= cut &&
            !late_events?(store:, from_datetime:, entry:)
        end

        def late_events?(store:, from_datetime:, entry:)
          where = [
            store.deduplicated_events_where_sql(from_datetime:, to_datetime: nil, before: entry.cut),
            ActiveRecord::Base.sanitize_sql_for_conditions(["enriched_at > ?", entry.watermark])
          ].join(" AND ")
          sql = "SELECT 1 FROM events_enriched WHERE #{where} LIMIT 1"

          Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
            connection.select_value(sql).present?
          end
        end

        def merge(left, right)
          aggregation_type = charge.billable_metric.aggregation_type

          (left.keys | right.keys).index_with do |filter_key|
            (left.fetch(filter_key, []) + right.fetch(filter_key, []))
              .group_by(&:groups)
              .map { |groups, rows| ChargeFiltersScan.combine(aggregation_type, groups, rows) }
          end
        end

        # The charge, its filters and its metric decide which events each filter keeps, so editing
        # any of them starts a new base.
        def cache_key(from_datetime:, to_datetime:, deduplicate:)
          [
            "charge-scan-incremental",
            CACHE_KEY_VERSION,
            Rails.cache.read(self.class.generation_key(subscription.id, charge.id)) || "0",
            subscription.id,
            charge.id,
            charge.updated_at.iso8601(6),
            charge.filters.map(&:updated_at).max&.iso8601(6),
            charge.billable_metric.updated_at.iso8601(6),
            from_datetime&.iso8601(6),
            to_datetime&.iso8601(6),
            deduplicate
          ].join("/")
        end

        def dump(entry)
          {
            "cut" => entry.cut.iso8601(6),
            "watermark" => entry.watermark.iso8601(6),
            "built_at" => entry.built_at.iso8601(6),
            "rows" => entry.rows.transform_values do |rows|
              rows.map { [it.groups, it.value&.to_s, it.events_count, it.timestamp] }
            end
          }
        end

        def load(payload)
          Entry.new(
            cut: Time.zone.parse(payload["cut"]),
            watermark: Time.zone.parse(payload["watermark"]),
            built_at: Time.zone.parse(payload["built_at"]),
            rows: payload["rows"].transform_values do |rows|
              rows.map do |groups, value, events_count, timestamp|
                ChargeFiltersScan::Row.new(groups:, value: value && BigDecimal(value), events_count:, timestamp:)
              end
            end
          )
        end
      end
    end
  end
end
