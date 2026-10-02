# frozen_string_literal: true

# Value object for a structured payment term, stored as jsonb tagged by term_type
class PaymentTerm < Data.define(:term_type, :days, :day_of_month, :month_offset)
  FIELDS_BY_TERM_TYPE = {
    "due_on_receipt" => [],
    "net" => ["days"],
    "end_of_month" => [],
    "net_end_of_month" => ["days"],
    "days_end_of_month" => ["days"],
    "day_of_month" => ["day_of_month", "month_offset"]
  }.freeze

  def self.from_h(hash)
    hash = hash.to_h.with_indifferent_access

    new(
      term_type: hash[:term_type],
      days: hash[:days],
      day_of_month: hash[:day_of_month],
      month_offset: hash[:month_offset]
    )
  end

  def initialize(term_type:, days: nil, day_of_month: nil, month_offset: nil)
    term_type = term_type.to_s
    fields = FIELDS_BY_TERM_TYPE.fetch(term_type, [])

    super(
      term_type:,
      days: (days&.to_i if fields.include?("days")),
      day_of_month: (day_of_month&.to_i if fields.include?("day_of_month")),
      # If absent - next month (1) by default.
      month_offset: ((month_offset || 1).to_i if fields.include?("month_offset"))
    )
  end

  def to_h
    {
      "term_type" => term_type,
      "days" => days,
      "day_of_month" => day_of_month,
      "month_offset" => month_offset
    }.compact
  end

  # The legacy integer can only represent net and due_on_receipt.
  def net_payment_term_alias
    case term_type
    when "net" then days
    when "due_on_receipt" then 0
    when "end_of_month", "net_end_of_month", "days_end_of_month", "day_of_month" then nil
    else raise ArgumentError, "unknown term_type: #{term_type}"
    end
  end

  def due_date_for(issuing_date)
    issuing_date = issuing_date.to_date

    case term_type
    when "due_on_receipt" then issuing_date
    when "net" then issuing_date + days
    when "end_of_month" then issuing_date.end_of_month
    when "net_end_of_month" then issuing_date.end_of_month + days # US: EOM, then +N
    when "days_end_of_month" then (issuing_date + days).end_of_month # EU: +N, then EOM
    when "day_of_month" then day_of_month_due_date(issuing_date)
    else raise ArgumentError, "unknown term_type: #{term_type}"
    end
  end

  private

  # month_offset → clamp → roll forward (only reachable with offset 0) → re-clamp
  def day_of_month_due_date(issuing_date)
    due_date = clamped_day_in_month(issuing_date >> month_offset)

    if due_date < issuing_date
      clamped_day_in_month(due_date >> 1)
    else
      due_date
    end
  end

  # Clamp the configured day to the target month: day 31 → Sep 30 / Feb 28 (29 on leap years)
  def clamped_day_in_month(date)
    date.change(day: [day_of_month, date.end_of_month.day].min)
  end
end
