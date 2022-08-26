# frozen_string_literal: true

module Events
  class CreateBatchService < BaseService
    ALL_REQUIRED_PARAMS = %i[transaction_id code external_subscription_ids].freeze

    def validate_params(params:)
      missing_params = ALL_REQUIRED_PARAMS.select { |key| params[key].blank? }
      return result if missing_params.blank?

      result.fail!(code: 'missing_mandatory_param', details: missing_params)
    end

    def call(organization:, params:, timestamp:, metadata:)
      customer = organization.subscriptions.find_by(
        external_id: params[:external_subscription_ids]&.first
      )&.customer

      Events::ValidateCreationService.call(
        organization: organization,
        params: params,
        customer: customer,
        result: result,
        batch: true
      )
      return result unless result.success?

      events = []
      ActiveRecord::Base.transaction do
        params[:external_subscription_ids].each do |id|
          subscription = Subscription.find_by(external_id: id)
          event = organization.events.find_by(transaction_id: params[:transaction_id], subscription_id: subscription.id)

          if event
            events << event

            next
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

          events << event
        rescue ActiveRecord::RecordInvalid => e
          result.fail_with_validations!(e.record)

          SendWebhookJob.perform_later(
            :event,
            { input_params: params, error: result.error, organization_id: organization.id }
          ) if organization.webhook_url?

          return result
        end
      end

      result.events = events
      result
    end
  end
end
