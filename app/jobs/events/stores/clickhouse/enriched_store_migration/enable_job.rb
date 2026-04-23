# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module EnrichedStoreMigration
        class EnableJob < ApplicationJob
          queue_as "low_priority"

          def perform(enriched_store_migration)
            EnableService.call!(enriched_store_migration:)
          end
        end
      end
    end
  end
end
