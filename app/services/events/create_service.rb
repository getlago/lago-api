# frozen_string_literal: true

module Events
  class CreateService < BaseService
    def initialize(organization:, params:, timestamp:, metadata:)
      @organization = organization
      @params = params
      @timestamp = timestamp
      @metadata = metadata
      super
    end

    def call
      event = Event.new
      event.organization_id = organization.id
      event.code = params[:code]
      event.transaction_id = params[:transaction_id]
      event.external_customer_id = params[:external_customer_id]
      event.external_subscription_id = params[:external_subscription_id]
      event.properties = params[:properties] || {}
      event.metadata = metadata || {}
      event.timestamp = Time.zone.at(params[:timestamp] ? params[:timestamp].to_f : timestamp)

      if is_charge_package_group?
        event.properties[:current_package_count] = current_package_count
      end

      event.save!

      result.event = event

      produce_kafka_event(event)
      Events::PostProcessJob.perform_later(event:)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique
      result.single_validation_failure!(field: :transaction_id, error_code: 'value_already_exist')
    end

    private

    attr_reader :organization, :params, :timestamp, :metadata

    def produce_kafka_event(event)
      return if ENV['LAGO_KAFKA_BOOTSTRAP_SERVERS'].blank?

      Karafka.producer.produce_sync(
        topic: 'events-raw',
        payload: {
          organization_id: organization.id,
          external_customer_id: event.external_customer_id,
          external_subscription_id: event.external_subscription_id,
          transaction_id: event.transaction_id,
          timestamp: event.timestamp,
          code: event.code,
          properties: event.properties,
        }.to_json,
      )
    end

    def charge_model
      @charge_model ||= find_charge_model_by_code
    end
    
    def find_charge_model_by_code
      subscription = Subscription.find_by(external_id: params[:external_subscription_id])
      plan = Plan.find_by(id: subscription.plan_id)
      billable_metric = organization.billable_metrics.find_by(code: params[:code])
      
      Charge.where(plan: plan, billable_metric: billable_metric).first
    end

    def is_charge_package_group?
      charge_model&.charge_model == 'package_group'
    end

    def current_package_count
      charge_model&.charge_package_group&.current_package_count || 1
    end
  end
end
