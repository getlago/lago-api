# frozen_string_literal: true

module Clock
  # Fans the consumer out, one job per customer holding a pending segment.
  #
  # A tick of its own rather than a continuation of the producer's: a segment is also written
  # outside the clock, and the customers that owe an invoice are not the customers whose cards
  # came due. It reads what is pending, whoever wrote it.
  class ProcessBillingSegmentsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      pending_customer_ids.each { |customer_id| BillingSegments::ProcessJob.perform_later(customer_id) }
    end

    private

    # Everything pending, not everything due: the consumer does not filter by billing_at
    # either, so both ends agree on what "ready" means and a segment cannot sit unread
    # because two queries disagree.
    #
    # A deleted customer is not invoiced. Deleting one leaves their segments untouched, and
    # the join reaches them because BillingSegment#customer is `with_discarded` — history has
    # to resolve through it — while the job loads the customer back through the kept-only
    # default scope and raises. Their segments do stay pending; clearing them belongs to the
    # deletion, not to this scan.
    def pending_customer_ids
      BillingSegment.status_pending
        .joins(:customer)
        .where(customers: {deleted_at: nil})
        .distinct
        .pluck(:customer_id)
    end
  end
end
