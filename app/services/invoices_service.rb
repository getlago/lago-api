# frozen_string_literal: true

class InvoicesService < BaseService
  def create(subscription:, timestamp:)
    to_date = (Time.zone.at(timestamp) - 1.day).to_date

    from_date = case subscription.plan.interval.to_sym
                when :monthly
                  (Time.zone.at(timestamp) - 1.month).to_date
                when :yearly
                  (Time.zone.at(timestamp) - 1.year).to_date
                else
                  raise NotImplementedError
    end

    # On first billing period, subscription might start after the computed start of period
    # ei: if we bill on beginning of period, and user registered on the 15th, the invoice should
    #     start on the 15th (subscription date) and not on the 1st
    from_date = subscription.started_at.to_date if from_date < subscription.started_at

    invoice = Invoice.find_or_create_by!(
      subscription: subscription,
      from_date: from_date,
      to_date: to_date,
    )

    result.invoice = invoice
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end
end
