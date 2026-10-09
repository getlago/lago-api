# frozen_string_literal: true

class IndexContractRateCardsBillingClock < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # The clock index carried an `ended_date IS NULL` predicate, and the producer's selection
  # keeps cards that end in the future, so the predicate is never implied and Postgres reads
  # the table instead. Carrying ended_date as a second column serves the same selection and
  # discards an ended card without a heap fetch.
  #
  # Measured on 500k cards, 20% of them ended, median of nine runs:
  #
  #   index                              size    0.14% due   13% due
  #   none                                  —      45.5 ms   145.1 ms
  #   (next_billing_at)                  11 MB      6.2 ms   121.9 ms
  #   (next_billing_at) + ended IS NULL   8 MB     15.6 ms    94.7 ms   never chosen
  #   (next_billing_at, ended_date)      15 MB      2.9 ms    83.7 ms
  def change
    add_index :contract_rate_cards, %i[next_billing_at ended_date],
      where: "deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_contract_rate_cards_on_billing_clock"

    remove_index :contract_rate_cards,
      column: :next_billing_at,
      where: "deleted_at IS NULL AND ended_date IS NULL",
      algorithm: :concurrently,
      if_exists: true,
      name: "index_contract_rate_cards_on_next_billing_at"
  end
end
