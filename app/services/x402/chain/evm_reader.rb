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
      HEX_WORD = /\A0x\h{64}\z/
      HEX_QUANTITY = /\A0x\h+\z/
      NONCE = HEX_WORD

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
        (outcome != :unused) || safe_head_timestamp >= valid_before
      end

      private

      attr_reader :network, :payment, :payment_requirements, :since

      def outcome
        @outcome ||= begin
          raise ArgumentError, "since must be a Time" unless since.is_a?(Time)

          validate_payment!
          verify_chain!

          if authorization_used?
            classify(find_authorization_log)
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

      def classify(log)
        return :canceled if log["topics"].first == AUTHORIZATION_CANCELED

        transfer = authorized_transfer(log["transactionHash"])

        if transfer["topics"][2].downcase == "0x#{padded(payee)}" && transfer["data"].to_i(16) == value
          @identifier = log["transactionHash"]
          :settled
        else
          :superseded
        end
      end

      def authorized_transfer(hash)
        logs = receipt_logs(hash)
        index = logs.index { |entry| from_asset?(entry) && entry["topics"] == [AUTHORIZATION_USED, "0x#{padded(payer)}", nonce.downcase] }
        transfer = index && logs[index + 1]

        if transfer && from_asset?(transfer) && token_transfer_from_payer?(transfer)
          transfer
        else
          raise InconclusiveError, "the receipt for #{hash} doesn't show the authorization's transfer"
        end
      end

      def receipt_logs(hash)
        receipt = rpc.call("eth_getTransactionReceipt", [hash])

        if receipt.is_a?(Hash) && receipt["status"] == "0x1" && receipt["transactionHash"].to_s.casecmp?(hash) && receipt["logs"].is_a?(Array) && receipt["logs"].all?(Hash)
          receipt["logs"]
        else
          raise InconclusiveError, "no successful receipt for #{hash}"
        end
      end

      def token_transfer_from_payer?(entry)
        topics = entry["topics"]
        topics.is_a?(Array) && topics.size == 3 && topics.first(2) == [TRANSFER, "0x#{padded(payer)}"] && HEX_WORD.match?(topics[2].to_s) && HEX_WORD.match?(entry["data"].to_s)
      end

      def from_asset?(entry)
        entry["address"].to_s.casecmp?(asset)
      end

      def authorization_used?
        word = rpc.call("eth_call", [{"to" => asset, "data" => "#{AUTHORIZATION_STATE}#{padded(payer)}#{nonce.downcase.delete_prefix("0x")}"}, hex(safe_head_number)])

        if BOOLEAN_WORD.match?(word.to_s)
          word.end_with?("1")
        else
          raise InconclusiveError, "authorizationState answered #{word.inspect}"
        end
      end

      def find_authorization_log
        from_block = lower_bound
        to_block = upper_bound

        scan_logs(from_block, to_block, [AUTHORIZATION_USED, AUTHORIZATION_CANCELED]) ||
          scan_logs(to_block + 1, safe_head_number, [AUTHORIZATION_CANCELED]) ||
          raise(InconclusiveError, "the nonce is used but no AuthorizationUsed or AuthorizationCanceled event was found in blocks #{from_block}..#{safe_head_number}")
      end

      def scan_logs(from_block, to_block, events)
        (from_block..to_block).step(LOG_CHUNK_BLOCKS).first(MAX_LOG_CHUNKS).each do |chunk_start|
          chunk_end = [chunk_start + LOG_CHUNK_BLOCKS - 1, to_block].min
          logs = rpc.call("eth_getLogs", [{
            "address" => asset,
            "topics" => [events, "0x#{padded(payer)}", nonce.downcase],
            "fromBlock" => hex(chunk_start),
            "toBlock" => hex(chunk_end)
          }]) || []
          raise InconclusiveError, "eth_getLogs returned a malformed answer" unless logs.is_a?(Array) && logs.all? { |entry| usable_log?(entry) }

          log = logs.find { |entry| !entry["removed"] }
          return log if log
        end

        if to_block - from_block >= LOG_CHUNK_BLOCKS * MAX_LOG_CHUNKS
          raise InconclusiveError, "the log window over blocks #{from_block}..#{to_block} exceeds #{MAX_LOG_CHUNKS} chunks"
        end
      end

      def usable_log?(entry)
        entry.is_a?(Hash) && entry["topics"].is_a?(Array) && entry["transactionHash"].is_a?(String)
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
        time = [valid_before, safe_head_timestamp].min
        block = estimated_block(time) + MARGIN_BLOCKS

        MAX_BOUND_ATTEMPTS.times do
          return safe_head_number if block >= safe_head_number

          early = time - block_timestamp(block)
          return block if early <= 0

          block += (early.fdiv(SECONDS_PER_BLOCK).ceil + MARGIN_BLOCKS)
        end
        safe_head_number
      end

      def estimated_block(time)
        safe_head_number - (safe_head_timestamp - time).fdiv(SECONDS_PER_BLOCK).ceil
      end

      def safe_head
        @safe_head ||= read_block("safe", "no safe block")
      end

      def safe_head_number
        safe_head["number"].to_i(16)
      end

      def safe_head_timestamp
        safe_head["timestamp"].to_i(16)
      end

      def block_timestamp(number)
        read_block(hex(number), "block #{number} is unknown to the endpoint")["timestamp"].to_i(16)
      end

      def read_block(tag, missing)
        block = rpc.call("eth_getBlockByNumber", [tag, false])

        if block.is_a?(Hash) && HEX_QUANTITY.match?(block["number"].to_s) && HEX_QUANTITY.match?(block["timestamp"].to_s)
          block
        else
          raise InconclusiveError, missing
        end
      end

      def validate_payment!
        raise UnreadablePaymentError, "the stored EVM payment has no usable authorization" unless usable_authorization?
      end

      def usable_authorization?
        Network::EVM_ADDRESS.match?(asset.to_s) && [payer, payee].all? { |address| Network::EVM_ADDRESS.match?(address.to_s) } &&
          NONCE.match?(nonce.to_s) && [value, valid_after, valid_before].all?
      end

      def authorization
        @authorization ||= begin
          payload = object(payment)["payload"]
          object(payload.is_a?(Hash) ? payload["authorization"] : nil)
        end
      end

      def asset
        object(payment_requirements)["asset"]
      end

      def object(value)
        value.is_a?(Hash) ? value.deep_stringify_keys : {}
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
