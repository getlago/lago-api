# frozen_string_literal: true

class BillingPeriodBoundaries
  attr_reader :from_datetime,
    :to_datetime,
    :charges_from_datetime,
    :charges_duration,
    :timestamp,
    :issuing_date,
    :fixed_charges_from_datetime,
    :fixed_charges_to_datetime,
    :fixed_charges_duration
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
      issuing_date: props["issuing_date"],
      fixed_charges_from_datetime: props["fixed_charges_from_datetime"],
      fixed_charges_to_datetime: props["fixed_charges_to_datetime"],
      fixed_charges_duration: props["fixed_charges_duration"]
    )
  end

  def initialize(
    from_datetime:,
    to_datetime:,
    charges_from_datetime:,
    charges_to_datetime:,
    charges_duration:,
    timestamp:,
    issuing_date: nil,
    fixed_charges_from_datetime:,
    fixed_charges_to_datetime:,
    fixed_charges_duration:
    )

    @from_datetime = from_datetime
    @to_datetime = to_datetime
    @charges_from_datetime = charges_from_datetime
    @charges_to_datetime = charges_to_datetime
    @charges_duration = charges_duration
    @timestamp = timestamp
    @issuing_date = issuing_date
    @fixed_charges_from_datetime = fixed_charges_from_datetime
    @fixed_charges_to_datetime = fixed_charges_to_datetime
    @fixed_charges_duration = fixed_charges_duration
  end

  def to_h
    h = {
      "from_datetime" => from_datetime,
      "to_datetime" => to_datetime,
      "charges_from_datetime" => charges_from_datetime,
      "charges_to_datetime" => charges_to_datetime,
      "charges_duration" => charges_duration,
      "timestamp" => timestamp,
      "fixed_charges_from_datetime" => fixed_charges_from_datetime,
      "fixed_charges_to_datetime" => fixed_charges_to_datetime,
      "fixed_charges_duration" => fixed_charges_duration
    }.with_indifferent_access
    h["issuing_date"] = issuing_date if issuing_date.present?
    h
  end
end
