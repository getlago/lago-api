# frozen_string_literal: true

module BillingPeriodDateDiff
  extend ActiveSupport::Concern

  def date_diff_with_timezone(from_datetime, to_datetime)
    number_of_days = Utils::Datetime.date_diff_with_timezone(
      from_datetime,
      to_datetime,
      customer.applicable_timezone
    )

    return number_of_days unless upgraded_billing_period?

    number_of_days -= 1
    number_of_days.negative? ? 0 : number_of_days
  end

  private

  def upgraded_billing_period?
    respond_to?(:upgraded?) && terminated? && upgraded?
  end
end
