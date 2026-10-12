# frozen_string_literal: true

module X402
  module CreditPurchases
    class PurchaseService < BaseService
      Result = BaseResult[:settlement, :replayed]

      RACE_CODES = %w[payment_already_recorded credit_purchase_pending].freeze

      def initialize(organization:, params:)
        @organization = organization
        @params = params

        super
      end

      def call
        return refuse(:payment, "invalid_payment") unless payment.is_a?(Hash)
        return refuse(:payment_requirements, "invalid_payment_requirements") unless payment_requirements.is_a?(Hash)

        digest_result = X402::Payments::ComputeDigestService.call(payment:, network: payment_payload.network, asset: payment_payload.asset)
        return result.validation_failure!(errors: digest_result.error.messages) if digest_result.failure?

        replay = find_replay(digest_result.digest)
        return answer_replay(replay) if replay
        return result.not_found_failure!(resource: "connection") unless connection

        checks = ValidateService.call(connection:, params:)
        return result.fail_with_error!(checks.error) if checks.failure?

        verified_payment = verify
        return result unless verified_payment

        checks = ValidateService.call(connection:, params:, verified_payment:)
        if checks.success?
          settle(verified_payment)
        else
          result.fail_with_error!(checks.error)
        end
      end

      private

      attr_reader :organization, :params

      def connection
        @connection ||= organization.x402_connections.find_by(code: params[:connection_code])
      end

      def payment
        params[:payment]
      end

      def payment_requirements
        params[:payment_requirements]
      end

      def payment_payload
        @payment_payload ||= X402::PaymentPayload.new(payment:, payment_requirements:)
      end

      def purchase_settings
        @purchase_settings ||= {
          "plan_code" => params[:plan_code],
          "wallet_code" => params[:wallet_code],
          "wallet" => wallet_shape
        }.compact
      end

      def wallet_shape
        shape = params[:wallet]

        if shape.is_a?(Hash)
          shape.deep_stringify_keys.slice(*X402::Wallets::ResolveService::SHAPE_KEYS)
        end
      end

      def verify
        verification = X402::Settlements::VerifyService.call(connection:, payment:, payment_requirements:)

        if verification.success?
          verification.verified_payment
        else
          result.fail_with_error!(verification.error)
          nil
        end
      rescue X402::Facilitator::Error => e
        reason = e.class.name.demodulize.underscore
        result.third_party_failure!(third_party: connection.facilitator, error_code: reason, error_message: "#{reason}: #{e.message}")
        nil
      end

      def settle(verified_payment)
        settle_result = X402::Settlements::SettleService.call(verified_payment:, kind: :credit_purchase, purchase_settings:)
        return answer_lost_race(settle_result.error, verified_payment.payment_digest) if settle_result.failure?

        settlement = settle_result.settlement
        if settle_result.outcome == :settled && flip(settlement, settle_result.transaction_hash)
          grant(settlement, replayed: false)
        else
          answer(settlement, replayed: false)
        end
      end

      def find_replay(digest)
        organization.x402_settlements.where(status: %i[pending settled]).find_by(payment_digest: digest)
      end

      def answer_replay(settlement)
        return refuse_invoice_payment(settlement) if settlement.invoice_payment?

        Rails.logger.info("#{self.class.name} replay status=#{settlement.status} settings_changed=#{settlement.purchase_settings != purchase_settings}")

        if settlement.settled? && settlement.wallet_transaction_id.nil?
          grant(settlement, replayed: true)
        else
          answer(settlement, replayed: true)
        end
      end

      def refuse_invoice_payment(settlement)
        Rails.logger.warn("#{self.class.name} call failed reason=recorded_as_invoice_payment network=#{settlement.network}")
        refuse(:payment, "recorded_as_invoice_payment")
      end

      def answer_lost_race(error, digest)
        replay = lost_race?(error) && find_replay(digest)

        if replay
          answer_replay(replay)
        else
          result.fail_with_error!(error)
        end
      end

      def lost_race?(error)
        error.is_a?(BaseService::ValidationFailure) && RACE_CODES.include?(error.messages[:base]&.first)
      end

      def flip(settlement, transaction_hash)
        settlement.update!(status: :settled, transaction_hash:)
      rescue ActiveRecord::ActiveRecordError => e
        settlement.restore_attributes
        Rails.logger.warn("#{self.class.name} call failed reason=flip_failed error=#{e.class.name} network=#{settlement.network}")
        false
      end

      def grant(settlement, replayed:)
        grant_result = GrantService.call(settlement:)

        if grant_result.success?
          answer(grant_result.settlement, replayed:)
        else
          refuse_grant(grant_result.error, settlement)
        end
      end

      def refuse_grant(error, settlement)
        Rails.logger.warn("#{self.class.name} call failed reason=grant_failed error=#{error.class.name} message=#{error.message} network=#{settlement.network}")
        refuse(:base, "credit_grant_failed")
      end

      def answer(settlement, replayed:)
        result.settlement = settlement
        result.replayed = replayed
        result
      end

      def refuse(field, code)
        result.single_validation_failure!(error_code: code, field:)
      end
    end
  end
end
