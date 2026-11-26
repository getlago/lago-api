# frozen_string_literal: true

module Contracts
  class ConsumeRefreshedQueueService < BaseService
    Result = BaseResult

    REDIS_STORE_NAME = "contract_refreshed_v1"
    BATCH_SIZE = 100
    PROCESSING_TIMEOUT = 1.minute

    # events-processor writes org_id:external_contract_id|bucket members scored with their latest event,
    # so a member is read once no event has extended its bucket for this long.
    CONTRACT_BUCKET_DURATION = 10

    def call
      return result if ENV["LAGO_REDIS_STORE_URL"].blank?

      start_time = Time.current

      loop do
        break if Time.current - start_time > PROCESSING_TIMEOUT

        threshold = (Time.current - CONTRACT_BUCKET_DURATION).to_i
        values = redis_client.zrangebyscore(REDIS_STORE_NAME, "-inf", threshold, limit: [0, BATCH_SIZE])
        break if values.blank?

        values.each { |value| flag_refreshed(value) }

        redis_client.zrem(REDIS_STORE_NAME, values)
      end

      result
    end

    private

    # An external id may contain ":" or "|", while an organization id or a bucket never does.
    def flag_refreshed(value)
      organization_id, external_contract_id = value.rpartition("|").first.split(":", 2)
      return if organization_id.blank? || external_contract_id.blank?

      Contracts::FlagRefreshedJob.perform_later(organization_id, external_contract_id)
    end

    def redis_client
      return @redis_client if defined? @redis_client

      url = if ENV["LAGO_REDIS_STORE_URL"].start_with?(/rediss?:\/\//)
        ENV["LAGO_REDIS_STORE_URL"]
      else
        "redis://#{ENV["LAGO_REDIS_STORE_URL"]}"
      end

      config = {
        url:,
        timeout: 5.0,
        reconnect_attempts: 3
      }

      config[:password] = ENV["LAGO_REDIS_STORE_PASSWORD"] if ENV["LAGO_REDIS_STORE_PASSWORD"].present?
      config[:db] = ENV["LAGO_REDIS_STORE_DB"] if ENV["LAGO_REDIS_STORE_DB"].present?

      if ENV["LAGO_REDIS_STORE_SSL"].present? || ENV["LAGO_REDIS_STORE_URL"].start_with?("rediss:")
        config[:ssl] = true
      end

      if ENV["LAGO_REDIS_STORE_DISABLE_SSL_VERIFY"].present?
        config[:ssl_params] = {verify_mode: OpenSSL::SSL::VERIFY_NONE}
      end

      @redis_client ||= Redis.new(config)
    end
  end
end
