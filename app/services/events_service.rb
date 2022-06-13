# frozen_string_literal: true

class EventsService < BaseService
  def validate_params(params:)
    mandatory_augments = %i[transaction_id customer_id code]

    missing_arguments = mandatory_augments.select { |arg| params[arg].blank? }
    return result if missing_arguments.blank?

    result.fail!('missing_mandatory_param', nil, missing_arguments)
  end

  def create(organization:, params:, timestamp:, metadata:)
    event = organization.events.find_by(id: params[:transaction_id])

    if event
      result.event = event
      return result
    end

    unless current_customer(organization.id, params[:customer_id])
      result.fail!('missing_argument', 'customer does not exist')

      send_webhook_notice(organization, params)

      return result
    end

    unless valid_code?(params[:code], organization)
      result.fail!('missing_argument', 'code does not exist')

      send_webhook_notice(organization, params)

      return result
    end

    event = organization.events.new
    event.code = params[:code]
    event.transaction_id = params[:transaction_id]
    event.customer = current_customer
    event.properties = params[:properties] || {}
    event.metadata = metadata || {}

    event.timestamp = Time.zone.at(params[:timestamp]) if params[:timestamp]
    event.timestamp ||= timestamp

    event.save!

    result.event = event
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)

    send_webhook_notice(organization, params)

    result
  end

  private

  def current_customer(organization_id = nil, customer_id = nil)
    @current_customer ||= Customer.find_by(
      customer_id: customer_id,
      organization_id: organization_id,
    )
  end

  def valid_code?(code, organization)
    valid_codes = organization.billable_metrics.pluck(:code)

    valid_codes.include? code
  end

  def send_webhook_notice(organization, params)
    return unless organization.webhook_url?

    object = {
      input_params: params,
      error: result.error,
      organization_id: organization.id
    }

    SendWebhookJob.perform_later(:event, object)
  end
end
