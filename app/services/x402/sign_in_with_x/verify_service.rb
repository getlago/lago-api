# frozen_string_literal: true

module X402
  module SignInWithX
    class VerifyService < BaseService
      Result = BaseResult[:address, :family, :nonce]

      VERSION = "1"
      MAX_AGE = 5.minutes
      MAX_CLOCK_SKEW = 30.seconds
      NONCE_FORMAT = /\A[A-Za-z0-9]{8,64}\z/
      MAX_FIELD_LENGTH = 512
      MAX_SIGNATURE_LENGTH = 16_384
      MAX_RESOURCES = 10

      REQUIRED_FIELDS = %w[domain address statement uri version chainId type nonce issuedAt signature].freeze
      OPTIONAL_FIELDS = %w[expirationTime notBefore requestId signatureScheme].freeze
      TIMESTAMP_FIELDS = %w[issuedAt expirationTime notBefore].freeze
      TIMESTAMP_FORMAT = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/
      SIGNATURE_TYPES = {"eip155" => "eip191", "solana" => "ed25519"}.freeze
      EVM_SIGNATURE = /\A0x\h{130}\z/
      SVM_SIGNATURE_MAX_LENGTH = 88

      def initialize(payload:, allowed_origins:, networks:)
        @payload = payload
        @allowed_origins = allowed_origins
        @networks = networks
        super
      end

      def call
        error_code = shape_error || version_error || chain_error || origin_error || time_error || nonce_error ||
          signer_error

        if error_code
          result.single_validation_failure!(field: :siwx, error_code:)
        else
          result.address = payload["address"]
          result.family = X402::Network::FAMILIES.fetch(namespace)
          result.nonce = payload["nonce"]
          result
        end
      end

      private

      attr_reader :payload, :allowed_origins, :networks

      def shape_error
        "value_is_invalid" unless payload.is_a?(Hash) && valid_types? && valid_strings? && valid_values?
      end

      def valid_types?
        REQUIRED_FIELDS.all? { |field| payload[field].is_a?(String) } &&
          OPTIONAL_FIELDS.all? { |field| !payload.key?(field) || payload[field].is_a?(String) } &&
          (!payload.key?("resources") || valid_resources?)
      end

      def valid_resources?
        resources = payload["resources"]

        resources.is_a?(Array) && resources.size <= MAX_RESOURCES && resources.all?(String)
      end

      def valid_strings?
        texts = payload.slice(*REQUIRED_FIELDS, *OPTIONAL_FIELDS).except("signature").values + payload.fetch("resources", [])

        texts.all? { |text| valid_text?(text, MAX_FIELD_LENGTH) } && valid_text?(payload["signature"], MAX_SIGNATURE_LENGTH)
      end

      def valid_text?(value, max_length)
        value.length <= max_length && value.valid_encoding? &&
          (value.ascii_only? || value.encoding == Encoding::UTF_8) && !value.match?(/[\r\n]/)
      end

      def valid_values?
        !payload["statement"].empty? && timestamps.values.all?
      end

      def timestamps
        @timestamps ||= payload.slice(*TIMESTAMP_FIELDS).transform_values { |value| parse_time(value) }
      end

      def parse_time(value)
        match = TIMESTAMP_FORMAT.match(value)

        if match
          time = Time.iso8601(value)
          time if match.captures.map(&:to_i) == [time.year, time.month, time.day, time.hour, time.min, time.sec]
        end
      rescue ArgumentError
        nil
      end

      def version_error
        "unsupported_version" unless payload["version"] == VERSION
      end

      def chain_error
        environment = X402::Network::NETWORKS[payload["chainId"]]

        if environment.nil? || environment != X402::Network.environment(networks.first) ||
            SIGNATURE_TYPES[namespace] != payload["type"]
          "unsupported_chain"
        end
      end

      def namespace
        payload["chainId"].split(":", 2).first
      end

      def origin_error
        origins = allowed_origins.select { |origin| X402::Origin.host(origin) == payload["domain"] }

        if origins.empty?
          "domain_mismatch"
        elsif !origins.include?(X402::Origin.of(payload["uri"]))
          "uri_mismatch"
        end
      end

      def time_error
        now = Time.current
        issued_at, expiration_time, not_before = timestamps.values_at(*TIMESTAMP_FIELDS)

        if issued_at < now - MAX_AGE
          "issued_at_too_old"
        elsif issued_at > now + MAX_CLOCK_SKEW
          "issued_at_in_future"
        elsif expiration_time && expiration_time < now
          "expired"
        elsif not_before && not_before > now
          "not_yet_valid"
        end
      end

      def nonce_error
        "invalid_nonce" unless NONCE_FORMAT.match?(payload["nonce"])
      end

      def signer_error
        if namespace == "eip155"
          evm_signer_error
        elsif !valid_svm_signature?
          "invalid_signature"
        end
      end

      def evm_signer_error
        address = payload["address"]

        if !X402::Network::EVM_ADDRESS.match?(address) || X402::Network.checksum(address) != address
          "invalid_address"
        elsif recovered_evm_address != address
          "invalid_signature"
        end
      end

      def recovered_evm_address
        if EVM_SIGNATURE.match?(payload["signature"])
          digest = X402::Keccak256.digest("\x19Ethereum Signed Message:\n#{message.bytesize}#{message}")
          signature = [payload["signature"].delete_prefix("0x")].pack("H*")
          public_key = X402::Secp256k1.recover_public_key(digest:, signature:)

          X402::Network.checksum("0x#{X402::Keccak256.hexdigest(public_key.byteslice(1, 64)).last(40)}") if public_key
        end
      end

      def valid_svm_signature?
        public_key = X402::Base58.decode(payload["address"])
        signature = X402::Base58.decode(payload["signature"]) if payload["signature"].length <= SVM_SIGNATURE_MAX_LENGTH

        public_key&.bytesize == X402::Ed25519::PUBLIC_KEY_SIZE && signature&.bytesize == X402::Ed25519::SIGNATURE_SIZE &&
          X402::Ed25519.verify?(public_key:, signature:, message:)
      end

      def message
        @message ||= X402::SignInWithX::Message.build(payload)
      end
    end
  end
end
