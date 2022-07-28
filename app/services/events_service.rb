# frozen_string_literal: true

class EventsService < BaseService
  def validate_params(params:)
    mandatory_arguments = %i[transaction_id code]
    mandatory_subscription_arguments = %i[subscription_id customer_id]

    missing_arguments = mandatory_arguments.select { |arg| params[arg].blank? }
    missing_subscription_arguments = mandatory_subscription_arguments.select { |arg| params[arg].blank? }
    return result if missing_arguments.blank? && missing_subscription_arguments.count <= 1

    result.fail!('missing_mandatory_param', nil, missing_arguments + missing_subscription_arguments)
  end

  def validate_batch_params(params:)
    mandatory_arguments = %i[transaction_id code subscription_ids]

    missing_arguments = mandatory_arguments.select { |arg| params[arg].blank? }
    return result if missing_arguments.blank?

    result.fail!('missing_mandatory_param', nil, missing_arguments)
  end

  def create(organization:, params:, timestamp:, metadata:)
    validate_create(organization, params)
    return result unless result.success?

    subscription_id = params[:subscription_id] || attached_subscriptions.first
    event = organization.events.find_by(transaction_id: params[:transaction_id], subscription_id: subscription_id)

    if event
      result.event = event
      return result
    end

    event = organization.events.new
    event.code = params[:code]
    event.transaction_id = params[:transaction_id]
    event.customer = current_customer
    event.subscription_id = subscription_id
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

  def batch_create(organization:, params:, timestamp:, metadata:)
    validate_batch_create(organization, params)
    return result unless result.success?

    events = []
    ActiveRecord::Base.transaction do
      params[:subscription_ids].each do |id|
        event = organization.events.find_by(transaction_id: params[:transaction_id], subscription_id: id)

        if event
          events << event

          next
        end

        event = organization.events.new
        event.code = params[:code]
        event.transaction_id = params[:transaction_id]
        event.customer = current_customer
        event.subscription_id = id
        event.properties = params[:properties] || {}
        event.metadata = metadata || {}

        event.timestamp = Time.zone.at(params[:timestamp]) if params[:timestamp]
        event.timestamp ||= timestamp

        event.save!

        events << event
      rescue ActiveRecord::RecordInvalid => e
        result.fail_with_validations!(e.record)

        send_webhook_notice(organization, params)

        return result
      end
    end

    result.events = events

    result
  end

  private

  def validate_create(organization, params)
    unless current_customer(organization, params[:customer_id], params[:subscription_id])
      return invalid_customer_error(organization, params)
    end

    if attached_subscriptions.count > 1
      return blank_subscription_error(organization, params) if params[:subscription_id].blank?
      unless attached_subscriptions.include?(params[:subscription_id])
        return invalid_subscription_error(organization, params)
      end
    elsif params[:subscription_id]
      unless attached_subscriptions.include?(params[:subscription_id])
        return invalid_subscription_error(organization, params)
      end
    else
      return blank_subscription_error(organization, params) if attached_subscriptions.blank?
    end

    return invalid_code_error(organization, params) unless valid_code?(params[:code], organization)
  end

  def validate_batch_create(organization, params)
    return blank_subscription_error(organization, params) if params[:subscription_ids].blank?
    unless current_customer(organization, params[:customer_id], params[:subscription_ids]&.first)
      return invalid_customer_error(organization, params)
    end

    invalid_subscriptions = params[:subscription_ids].select { |arg| !attached_subscriptions.include?(arg) }
    return invalid_subscription_error(organization, params) if invalid_subscriptions.present?
    return invalid_code_error(organization, params) unless valid_code?(params[:code], organization)
  end

  def current_customer(organization = nil, customer_id = nil, subscription_id = nil)
    return @current_customer if defined? @current_customer

    @current_customer = if subscription_id
                          organization.subscriptions.find_by(id: subscription_id)&.customer
                        else
                          Customer.find_by(customer_id: customer_id, organization_id: organization.id)
                        end
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

  def attached_subscriptions
    @attached_subscriptions ||= current_customer&.active_subscriptions&.pluck(:id)
  end

  def blank_subscription_error(organization, params)
    result.fail!('missing_argument', 'subscription does not exist or is not given')
    send_webhook_notice(organization, params)
  end

  def invalid_subscription_error(organization, params)
    result.fail!('invalid_argument', 'subscription_id is invalid')
    send_webhook_notice(organization, params)
  end

  def invalid_code_error(organization, params)
    result.fail!('missing_argument', 'code does not exist')
    send_webhook_notice(organization, params)
  end

  def invalid_customer_error(organization, params)
    result.fail!('missing_argument', 'customer cannot be found')
    send_webhook_notice(organization, params)
  end
end
