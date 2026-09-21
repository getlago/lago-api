# frozen_string_literal: true

module Clock
  # Fans the consumer out, one job per customer holding a processable segment.
  #
  # A tick of its own rather than a continuation of the producer's: a segment is also written
  # outside the clock, and the customers that owe an invoice are not the customers whose cards
  # came due. It reads every pending or processing segment, whoever wrote it.
  class ProcessBillingSegmentsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      processable_customer_ids.each { |customer_id| BillingSegments::ProcessJob.perform_later(customer_id) }
    end

    private

    def processable_customer_ids
      BillingSegment
        .where(status: %i[pending processing])
        .distinct
        .pluck(:customer_id)
    end
  end
end
