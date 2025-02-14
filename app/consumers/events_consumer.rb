# frozen_string_literal: true

class EventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      event_payload = message.payload

      event = Events::CommonFactory.new_instance source: event_payload

      # make sure Billable metric exists
      bm = BillableMetric.find_by(code: event.code, organization_id: event.organization_id)
      if !bm
        dispatch_to_dlq(message)
        next
      end

      # Evaluate expression
      expression_result = Events::CalculateExpressionService.call(organization: event.organization, event:)
      if expression_result.failure?
        dispatch_to_dlq(message)
        next
      end

      # Check pay in advance
      if event_payload["source"] != "http_ruby" && bm.charges.pay_in_advance.exists?
        Events::PayInAdvanceKafkaJob.perform_later(event.as_json)
      end

      # fill in value with the extracted value
      value = event.properties[bm.field_name]
      event_payload["value"] = value.to_s

      producer.produce_async(
        topic: ENV["LAGO_KAFKA_ENRICHED_EVENTS_TOPIC"],
        key: "#{event.organization_id}-#{event.external_subscription_id}-#{event.code}",
        payload: event_payload.to_json
      )
      mark_as_consumed(message)
    end
  end
end
