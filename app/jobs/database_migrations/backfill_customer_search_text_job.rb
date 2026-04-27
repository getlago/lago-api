# frozen_string_literal: true

module DatabaseMigrations
  class BackfillCustomerSearchTextJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed

    BATCH_SIZE = 1_000

    def perform
      rows_updated = ActiveRecord::Base.connection.execute(<<~SQL.squish).cmd_tuples
        UPDATE customers
        SET search_text = CONCAT_WS(' ', name, firstname, lastname, external_id, email)
        WHERE id IN (
          SELECT id FROM customers
          WHERE search_text = '' OR search_text IS NULL
          LIMIT #{BATCH_SIZE}
        )
      SQL

      if rows_updated.positive?
        self.class.perform_later
      else
        Rails.logger.info("Finished backfilling customer search_text")
      end
    end
  end
end
