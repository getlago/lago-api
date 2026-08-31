# frozen_string_literal: true

module StreamingDestinations
  class DeliverJob < ApplicationJob
    # TODO: Move to a dedicated :streaming queue so a backed-up stream cannot
    #       starve HTTP webhook delivery. That needs a new process config under
    #       config/sidekiq/ plus a deployment change in lago-infrastructure,
    #       both out of scope for this POC.
    queue_as :webhook

    # Kinesis throttles per shard. Named as a string because aws-sdk-kinesis is
    # `require: false`, so the constant is not loaded when this class is.
    retry_on "Aws::Kinesis::Errors::ProvisionedThroughputExceededException", wait: :polynomially_longer

    # Stays provider-blind: the destination names its own delivery service. The
    # result is deliberately not raised on, so a permanently undeliverable record
    # (see the size cap in the Kinesis service) does not start a retry storm.
    # Transport errors reach us as exceptions and are retried above.
    def perform(destination:, payload:, partition_key:)
      destination.deliver_service_class.call(destination:, payload:, partition_key:)
    end
  end
end
