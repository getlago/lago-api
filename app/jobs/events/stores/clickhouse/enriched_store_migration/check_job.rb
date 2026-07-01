# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module EnrichedStoreMigration
        class CheckJob < ApplicationJob
          queue_as "low_priority"

          def perform(enriched_store_migration)
            CheckService.call!(enriched_store_migration:)
          end
        end
      end
    end
  end
end
