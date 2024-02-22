# frozen_string_literal: true

module TimebasedEvents
  class CreateService < BaseService
    def initialize(organization:, params:, timestamp:, metadata:, async: false)
      @organization = organization
      @params = params
      @timestamp = timestamp
      @metadata = metadata
      super
    end

    def call
      timebased_event = TimebasedEvent.new
      timebased_event.organization = organization
      timebased_event.external_customer_id = params[:external_customer_id]
      timebased_event.external_subscription_id = params[:external_subscription_id]
      timebased_event.metadata = metadata
      timebased_event.timestamp = Time.zone.at(params[:timestamp] ? params[:timestamp].to_f : timestamp)
      timebased_event.event_type = params[:event_type]

      timebased_event.save!

      return Subscriptions::RenewalJob.perform_later(timebased_event:) if async

      renewal_result = Subscriptions::RenewalService.new(timebased_event: timebased_event, async: false).call
      if renewal_result.already_renewed
        result.already_renewed = true
        return result
      end

      if renewal_result.success?
        # timebased_event.update(invoice: renewal_result.invoice)
      end

      result.timebased_event = timebased_event
      result
    end

    private

    attr_reader :organization, :params, :timestamp, :metadata, :async
  end
end
