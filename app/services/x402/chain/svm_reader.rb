# frozen_string_literal: true

module X402
  module Chain
    class SvmReader
      PAGE_SIZE = 1_000
      MAX_PAGES = 50
      MAX_WINDOW_PAGES = 5
      SINCE_MARGIN = 10.minutes
      LANDING_WINDOW = 10.minutes
      EXPIRY_PROOF = 120.seconds
      COMMITMENT = "finalized"

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
        (outcome != :absent) || blockhash_expired?
      end

      private

      attr_reader :network, :payment, :payment_requirements, :since

      def outcome
        @outcome ||= begin
          raise ArgumentError, "since must be a Time" unless since.is_a?(Time)

          buyer_signature
          verify_cluster!
          expiry
          match = find_landed_transaction

          if match.nil?
            :absent
          elsif succeeded?(match)
            @identifier = match[:signature]
            :settled
          else
            :failed_on_chain
          end
        end
      end

      def find_landed_transaction
        before = nil
        window_pages = 0

        MAX_PAGES.times do
          page = history_page(before)
          candidates = page.reject { |entry| entry["blockTime"] && entry["blockTime"] > since.to_i + LANDING_WINDOW.to_i }
          window_pages += 1 if candidates.any?
          raise InconclusiveError, "the buyer's history around the payment exceeds #{MAX_WINDOW_PAGES} pages" if window_pages > MAX_WINDOW_PAGES

          candidates.each do |entry|
            return nil if entry["blockTime"] && entry["blockTime"] < since.to_i - SINCE_MARGIN.to_i

            match = match_candidate(entry)
            return match if match
          end

          return nil if page.size < PAGE_SIZE

          before = page.last["signature"]
        end

        raise InconclusiveError, "the buyer's history since the payment exceeds #{MAX_PAGES} pages"
      end

      def history_page(before)
        page = rpc.call("getSignaturesForAddress", [Base58.encode(authority), signature_query(before)]) || []

        if page.is_a?(Array) && page.all? { |entry| signature_entry?(entry) }
          page
        else
          raise InconclusiveError, "getSignaturesForAddress returned a malformed page"
        end
      end

      def signature_entry?(entry)
        entry.is_a?(Hash) && entry["signature"].is_a?(String) && (entry["blockTime"].nil? || entry["blockTime"].is_a?(Integer))
      end

      def match_candidate(entry)
        landed = rpc.call("getTransaction", [entry["signature"], {"encoding" => "json", "commitment" => COMMITMENT, "maxSupportedTransactionVersion" => 1}])
        raise InconclusiveError, "getTransaction returned no transaction for a listed signature" unless landed.is_a?(Hash)

        signatures = landed["transaction"].is_a?(Hash) && landed["transaction"]["signatures"]
        raise InconclusiveError, "getTransaction returned no signatures for #{entry["signature"]}" unless signatures.is_a?(Array)

        {signature: entry["signature"], transaction: landed} if signatures.include?(Base58.encode(buyer_signature))
      end

      def succeeded?(match)
        meta = match[:transaction]["meta"]
        raise InconclusiveError, "getTransaction returned no status for #{match[:signature]}" unless meta.is_a?(Hash) && meta.key?("err")

        meta["err"].nil?
      end

      def signature_query(before)
        query = {"limit" => PAGE_SIZE, "commitment" => COMMITMENT, "minContextSlot" => expiry["context"]["slot"]}
        before ? query.merge("before" => before) : query
      end

      def blockhash_expired?
        return @blockhash_expired if defined?(@blockhash_expired)

        @blockhash_expired = expiry["value"] == false && slot_dated_past_expiry?
      end

      def slot_dated_past_expiry?
        slot_time = rpc.call("getBlockTime", [expiry["context"]["slot"]])

        if slot_time.nil? || slot_time.is_a?(Integer)
          slot_time.present? && slot_time >= since.to_i + EXPIRY_PROOF.to_i
        else
          raise InconclusiveError, "getBlockTime answered something other than a time"
        end
      end

      def verify_cluster!
        reference = network.to_s.split(":", 2).last
        raise InconclusiveError, "the endpoint for #{network} serves another cluster" unless rpc.call("getGenesisHash", []).to_s.start_with?(reference)
      end

      def expiry
        @expiry ||= begin
          answer = rpc.call("isBlockhashValid", [Base58.encode(transaction.recent_blockhash), {"commitment" => COMMITMENT}])

          if answer.is_a?(Hash) && answer["context"].is_a?(Hash) && answer["context"]["slot"].is_a?(Integer) && [true, false].include?(answer["value"])
            answer
          else
            raise InconclusiveError, "isBlockhashValid returned no usable answer"
          end
        end
      end

      def transaction
        @transaction ||= begin
          stored = SolanaTransaction.decode(Base64.strict_decode64(stored_transaction.to_s))
          raise UnreadablePaymentError, "the stored Solana transaction uses a durable nonce and never expires" if stored.durable_nonce?
          raise UnreadablePaymentError, "the stored Solana transaction has no TransferChecked" unless stored.transfer_checked

          stored
        end
      rescue ArgumentError
        raise UnreadablePaymentError, "the stored Solana transaction is not base64"
      end

      def stored_transaction
        payload = object(payment)["payload"]
        payload.is_a?(Hash) ? payload["transaction"] : nil
      end

      def object(value)
        value.is_a?(Hash) ? value.deep_stringify_keys : {}
      end

      def authority
        transaction.account_keys[transaction.transfer_checked.accounts[3]]
      end

      def buyer_signature
        @buyer_signature ||= begin
          signature = authority && transaction.signature_for(authority)
          raise UnreadablePaymentError, "the TransferChecked authority is not a signer" if signature.nil? || signature.count("\x00") == signature.bytesize

          signature
        end
      end

      def rpc
        @rpc ||= RpcClient.new(network:)
      end
    end
  end
end
