# frozen_string_literal: true

module EventDestinations
  # Thin wrapper over the Kinesis SDK. In log mode the client is stubbed, so the SDK still
  # validates the request parameters but nothing leaves the process: going live is a
  # constructor change, not a redesign.
  class KinesisProducer
    # A dead destination must not hold a Sidekiq thread for minutes. The SDK defaults
    # (15s connect, 60s read, 3 retries) allow up to 240s per record; these cap it near 14s.
    # Dropping a snapshot is cheap: the next wallet refresh re-emits it with a newer version.
    HTTP_OPEN_TIMEOUT = 2
    HTTP_READ_TIMEOUT = 5
    RETRY_LIMIT = 1

    def initialize(stream:)
      @stream = stream
    end

    def produce(data:, partition_key:)
      payload = JSON.generate(data)

      response = client.put_record(
        stream_arn: stream.stream_arn,
        data: payload,
        partition_key:
      )

      Rails.logger.info(log_line(payload, partition_key, response))

      response
    end

    private

    attr_reader :stream

    def log_line(payload, partition_key, response)
      line = "[event_destinations] put_record stream=#{stream.stream_arn} " \
             "partition_key=#{partition_key} bytes=#{payload.bytesize}"

      if stream.log_only?
        # Stubbed responses carry placeholder ids, so the payload is the useful evidence here.
        "#{line} data=#{payload}"
      else
        # With no read access to a customer's stream, these are the only proof a record landed.
        "#{line} shard=#{response.shard_id} sequence=#{response.sequence_number}"
      end
    end

    def client
      @client ||= Aws::Kinesis::Client.new(
        region: stream.region,
        stub_responses: stream.log_only?,
        http_open_timeout: HTTP_OPEN_TIMEOUT,
        http_read_timeout: HTTP_READ_TIMEOUT,
        retry_limit: RETRY_LIMIT
      ).tap do |kinesis|
        # The SDK does not check this itself: with unresolvable credentials it fails deep in
        # endpoint construction with `undefined method 'credentials' for nil`, which says
        # nothing about the actual problem.
        raise Aws::Errors::MissingCredentialsError if kinesis.config.credentials.nil?
      end
    end
  end
end
