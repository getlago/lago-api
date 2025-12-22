# frozen_string_literal: true

module Integrations
  module NetsuiteV2
    class KafkaProducerService < Integrations::BaseKafkaProducerService
      TOPIC_ENV_VAR = "LAGO_KAFKA_NETSUITE_V2_TOPIC"

      def self.topic_configured?
        ENV[TOPIC_ENV_VAR].present?
      end

      private

      def topic
        ENV[TOPIC_ENV_VAR]
      end
    end
  end
end
