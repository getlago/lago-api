# frozen_string_literal: true

class SetEventsEnrichedAtDefaultToNow64 < ActiveRecord::Migration[8.0]
  TABLES = %w[events_enriched events_enriched_expanded].freeze

  # now() returns a DateTime, whose resolution is one second, so inserting it into the
  # DateTime64(3) enriched_at column zero-filled the fraction. Every event enriched within the
  # same second got an identical enriched_at, which made MAX(enriched_at) unable to distinguish
  # two separate inserts landing in that second and broke the lazy usage cache invalidation.
  # now64(3) reads the clock with sub-second precision. Column type is unchanged, so this only
  # updates the default expression and does not rewrite existing data.
  def up
    safety_assured do
      TABLES.each do |table|
        execute "ALTER TABLE #{table} MODIFY COLUMN enriched_at DateTime64(3) DEFAULT now64(3)"
      end
    end
  end

  def down
    safety_assured do
      TABLES.each do |table|
        execute "ALTER TABLE #{table} MODIFY COLUMN enriched_at DateTime64(3) DEFAULT now()"
      end
    end
  end
end
