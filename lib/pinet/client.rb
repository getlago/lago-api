# frozen_string_literal: true

module Pinet
  class Client
    PINET_API_URL = ENV.fetch('PINET_API_URL', 'default')
    RETRY_INTERVAL = 0.5 # seconds
    TIMEOUT = 5 # seconds

    def initialize(is_sync: false)
      @authorization_token = JwtService.create_jwt
      @is_sync = is_sync
    end

    def conn
      @conn ||= Faraday.new(url: PINET_API_URL) do |faraday|
        faraday.headers['Authorization'] = "Bearer #{@authorization_token}"
        faraday.request(:url_encoded)
        faraday.adapter(Faraday.default_adapter)
      end
    end

    def charge(payload)
      response = conn.post do |req|
        req.url('/api/v1/transactions.json')
        req.headers['Content-Type'] = 'application/json'
        req.body = {
          transaction: {
            amount: payload[:amount],
            currency: payload[:currency],
            payment_token: payload[:payment_token],
            description: payload[:description],
          },
        }.to_json
      end

      result = JSON.parse(response.body)

      return handle_transaction_result(result, 'failed') unless response.status == 201
      return handle_transaction_result(result) unless result['state'] == 'requested' && @is_sync

      transaction = retrieve_transaction(result['id'])
      handle_transaction_result(transaction)
    end

    private

    def retrieve_transaction(transaction_id)
      start_time = Time.now.utc.to_i
      transaction = nil

      loop do
        sleep(RETRY_INTERVAL)

        response = conn.get do |req|
          req.url("/api/v1/transactions/#{transaction_id}.json")
          req.headers['Content-Type'] = 'application/json'
        end

        result = JSON.parse(response.body)
        return result if response.status == 200 && %w[completed failed].include?(result['state'])

        transaction = result if response.status == 200

        break if Time.now.utc.to_i - start_time >= TIMEOUT
      end

      transaction
    end

    def handle_transaction_result(transaction_json, created_status = nil)
      created_status ||= transaction_json['state']
      raise StandardError, transaction_json['error'] || transaction_json if created_status == 'failed'

      {
        id: transaction_json['id'],
        amount: transaction_json['amount'],
        currency: transaction_json['currency'],
        status: transaction_json['state'],
      }
    end
  end
end
