# frozen_string_literal: true

class BillingPeriodBoundaries
  attr_reader :from_datetime, :to_datetime, :charges_from_datetime, :charges_duration, :timestamp, :issuing_date
  attr_accessor :charges_to_datetime

  def self.from_fee(fee)
    props = fee&.properties || {}

    new(
      from_datetime: props["from_datetime"],
      to_datetime: props["to_datetime"],
      charges_from_datetime: props["charges_from_datetime"],
      charges_to_datetime: props["charges_to_datetime"],
      charges_duration: props["charges_duration"],
      timestamp: props["timestamp"],
      issuing_date: props["issuing_date"]
    )
  end

  def initialize(from_datetime:, to_datetime:, charges_from_datetime:, charges_to_datetime:, charges_duration:, timestamp:, issuing_date: nil)
    @from_datetime = from_datetime
    @to_datetime = to_datetime
    @charges_from_datetime = charges_from_datetime
    @charges_to_datetime = charges_to_datetime
    @charges_duration = charges_duration
    @timestamp = timestamp
    @issuing_date = issuing_date
  end

  def to_h
    h = {
      "from_datetime" => from_datetime,
      "to_datetime" => to_datetime,
      "charges_from_datetime" => charges_from_datetime,
      "charges_to_datetime" => charges_to_datetime,
      "charges_duration" => charges_duration,
      "timestamp" => timestamp
    }.with_indifferent_access
    h["issuing_date"] = issuing_date if issuing_date.present?
    h
  end
end
