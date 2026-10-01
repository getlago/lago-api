# frozen_string_literal: true

module X402
  module Chain
    class EvmReader
      AUTHORIZATION_STATE = "0xe94a0102"
      AUTHORIZATION_USED = "0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5"
      AUTHORIZATION_CANCELED = "0x1cdd46ff242716cdaa72d159d339a485b3438398348d68f09d7c8c0a59353d81"
      TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

      SECONDS_PER_BLOCK = 2
      MARGIN_BLOCKS = 150
      LOOKBACK = 10.minutes
      LOG_CHUNK_BLOCKS = 1_000
      MAX_LOG_CHUNKS = 50
      MAX_BOUND_ATTEMPTS = 3

      BOOLEAN_WORD = /\A0x0{63}[01]\z/
      NONCE = /\A0x\h{64}\z/

      def initialize(network:, payment:, payment_requirements:, since:)
        @network = network
        @payment = payment
        @payment_requirements = payment_requirements
        @since = since
      end

      def settled?
        outcome == :settled
      end

      def identifier
        @identifier if settled?
      end

      def final?
        case outcome
        when :unused then head_timestamp >= valid_before
        when :unsafe then false
        else true
        end
      end

      private

      attr_reader :network, :payment, :payment_requirements, :since

      def outcome
        @outcome ||= begin
          validate_payment!
          verify_chain!

          if authorization_used?
            log = find_authorization_log
            safe?(log) ? classify(log) : :unsafe
          else
            :unused
          end
        end
      end

      def verify_chain!
        expected = network.to_s.split(":", 2).last.to_i
        actual = rpc.call("eth_chainId", []).to_s.to_i(16)
        raise InconclusiveError, "the endpoint for #{network} serves another chain (#{actual})" unless actual == expected
      end

      def safe?(log)
        safe_block = rpc.call("eth_getBlockByNumber", ["safe", false]) || raise(InconclusiveError, "no safe block")
        log["blockNumber"].to_s.to_i(16) <= safe_block["number"].to_i(16)
      end

      def classify(log)
        return :canceled if log["topics"].first == AUTHORIZATION_CANCELED

        receipt = rpc.call("eth_getTransactionReceipt", [log["transactionHash"]])
        raise InconclusiveError, "no successful receipt for #{log["transactionHash"]}" unless receipt && receipt["status"] == "0x1"
        return :superseded unless paid_payee?(receipt)

        @identifier = log["transactionHash"]
        :settled
      end

      def authorization_used?
        word = rpc.call("eth_call", [{"to" => asset, "data" => "#{AUTHORIZATION_STATE}#{padded(payer)}#{nonce.downcase.delete_prefix("0x")}"}, hex(head_number)])
        raise InconclusiveError, "authorizationState answered #{word.inspect}" unless BOOLEAN_WORD.match?(word.to_s)

        word.end_with?("1")
      end

      def find_authorization_log
        from_block = lower_bound
        to_block = upper_bound

        (from_block..to_block).step(LOG_CHUNK_BLOCKS).first(MAX_LOG_CHUNKS).each do |chunk_start|
          chunk_end = [chunk_start + LOG_CHUNK_BLOCKS - 1, to_block].min
          logs = rpc.call("eth_getLogs", [{
            "address" => asset,
            "topics" => [[AUTHORIZATION_USED, AUTHORIZATION_CANCELED], "0x#{padded(payer)}", nonce.downcase],
            "fromBlock" => hex(chunk_start),
            "toBlock" => hex(chunk_end)
          }])
          log = Array(logs).find { |entry| !entry["removed"] }
          return log if log
        end

        raise InconclusiveError, "the nonce is used but no AuthorizationUsed event was found in blocks #{from_block}..#{to_block}"
      end

      def paid_payee?(receipt)
        Array(receipt["logs"]).any? do |entry|
          entry["address"].to_s.casecmp?(asset) &&
            entry["topics"] == [TRANSFER, "0x#{padded(payer)}", "0x#{padded(payee)}"] &&
            entry["data"].to_s.to_i(16) == value
        end
      end

      def lower_bound
        time = [valid_after, since.to_i - LOOKBACK.to_i].max
        block = estimated_block(time) - MARGIN_BLOCKS

        MAX_BOUND_ATTEMPTS.times do
          return 0 if block <= 0

          late = block_timestamp(block) - time
          return block if late <= 0

          block -= (late.fdiv(SECONDS_PER_BLOCK).ceil + MARGIN_BLOCKS)
        end
        raise InconclusiveError, "could not find a block before #{time}"
      end

      def upper_bound
        time = [valid_before, head_timestamp].min
        block = estimated_block(time) + MARGIN_BLOCKS

        MAX_BOUND_ATTEMPTS.times do
          return head_number if block >= head_number

          early = time - block_timestamp(block)
          return block if early <= 0

          block += (early.fdiv(SECONDS_PER_BLOCK).ceil + MARGIN_BLOCKS)
        end
        head_number
      end

      def estimated_block(time)
        head_number - (head_timestamp - time).fdiv(SECONDS_PER_BLOCK).ceil
      end

      def head
        @head ||= rpc.call("eth_getBlockByNumber", ["latest", false]) || raise(InconclusiveError, "no head block")
      end

      def head_number
        head["number"].to_i(16)
      end

      def head_timestamp
        head["timestamp"].to_i(16)
      end

      def block_timestamp(number)
        block = rpc.call("eth_getBlockByNumber", [hex(number), false])
        raise InconclusiveError, "block #{number} is unknown to the endpoint" unless block

        block["timestamp"].to_i(16)
      end

      def validate_payment!
        return if Network::EVM_ADDRESS.match?(asset.to_s) && [payer, payee].all? { |address| Network::EVM_ADDRESS.match?(address.to_s) } &&
          NONCE.match?(nonce.to_s) && [value, valid_after, valid_before].all?

        raise UnreadablePaymentError, "the stored EVM payment has no usable authorization"
      end

      def authorization
        @authorization ||= payment.to_h.deep_stringify_keys.dig("payload", "authorization") || {}
      end

      def asset
        payment_requirements.to_h.deep_stringify_keys["asset"]
      end

      def payer
        authorization["from"]
      end

      def payee
        authorization["to"]
      end

      def nonce
        authorization["nonce"]
      end

      def value
        UnsignedInteger.parse(authorization["value"])
      end

      def valid_after
        UnsignedInteger.parse(authorization["validAfter"])
      end

      def valid_before
        UnsignedInteger.parse(authorization["validBefore"])
      end

      def padded(address)
        address.delete_prefix("0x").downcase.rjust(64, "0")
      end

      def hex(number)
        "0x#{number.to_s(16)}"
      end

      def rpc
        @rpc ||= RpcClient.new(network:)
      end
    end
  end
end
