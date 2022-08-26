# frozen_string_literal: true

module Events
  class CreateService < BaseService
    ALL_REQUIRED_PARAMS = %i[transaction_id code].freeze
    ONE_REQUIRED_PARAMS = %i[external_subscription_id external_customer_id].freeze

    def validate_params(params:)
      missing_params = ALL_REQUIRED_PARAMS.select { |key| params[key].blank? }
      missing_params |= ONE_REQUIRED_PARAMS if ONE_REQUIRED_PARAMS.all? { |key| params[key].blank? }

      # NOTE: In case of multiple subscriptions, we return an error if subscription_id is not given.
      if params[:external_customer_id].present? && params[:external_subscription_id].blank?
        customer = Customer.find_by(external_id: params[:external_customer_id])
        subscriptions_count = customer ? customer.active_subscriptions.count : 0
        missing_params |= %i[external_subscription_id] if subscriptions_count > 1
      end

      return result if missing_params.blank?

      result.fail!(code: 'missing_mandatory_param', details: missing_params)
    end

    def call(organization:, params:, timestamp:, metadata:)
      customer = if params[:external_subscription_id]
        organization.subscriptions.find_by(external_id: params[:external_subscription_id])&.customer
      else
        Customer.find_by(external_id: params[:external_customer_id], organization_id: organization.id)
      end

      Events::ValidateCreationService.call(
        organization: organization,
        params: params,
        customer: customer,
        result: result
      )

      return result unless result.success?

      subscription = Subscription.find_by(external_id: params[:external_subscription_id]) || customer&.active_subscriptions&.first
      event = organization.events.find_by(transaction_id: params[:transaction_id], subscription_id: subscription.id)

      if event
        result.event = event
        return result
      end

      event = organization.events.new
      event.code = params[:code]
      event.transaction_id = params[:transaction_id]
      event.customer = customer
      event.subscription_id = subscription.id
      event.properties = params[:properties] || {}
      event.metadata = metadata || {}

      event.timestamp = Time.zone.at(params[:timestamp]) if params[:timestamp]
      event.timestamp ||= timestamp

      event.save!

      result.event = event
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)

      SendWebhookJob.perform_later(
        :event,
        { input_params: params, error: result.error, organization_id: organization.id }
      ) if organization.webhook_url?

      result
    end
  end
end
