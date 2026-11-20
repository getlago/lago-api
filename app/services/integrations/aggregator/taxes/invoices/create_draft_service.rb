# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        class CreateDraftService < BaseService
          # reuse_tax_rates: the caller only needs an estimate (a wallet ongoing balance), so the
          # rates of an earlier answer may price it without calling the provider. Invoices and
          # previews never pass it, they always get the provider's exact answer.
          def initialize(invoice:, fees: nil, reuse_tax_rates: false)
            @reuse_tax_rates = reuse_tax_rates

            super(invoice:, fees:)
          end

          def action_name
            case provider
            when "anrok"
              "anrok-create-ephemeral-transaction"
            when "avalara"
              "request-tax-draft-invoice"
            end
          end

          def call
            return result unless integration
            return result unless ::Integrations::BaseIntegration::INTEGRATION_TAX_TYPES.include?(integration.type)
            return no_taxable_fees_result if taxable_fees.empty?

            body = rates_cache ? estimated_taxes : exact_taxes
            process_response(body)

            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError.new(e) if request_limit_error?(e)
            raise Integrations::Aggregator::BadGatewayError.new(e.error_body, e.uri) if bad_gateway_error?(e)
            raise Integrations::Aggregator::TaskInProgressError if task_in_progress_error?(e)
            raise Integrations::Aggregator::TaskExpiredError if task_expired_error?(e)
            raise Integrations::Aggregator::OrchestratorFailureError if orchestrator_failure_error?(e)

            code = code(e)
            message = message(e)

            result.service_failure!(code:, message:)
          rescue Net::ReadTimeout, Net::OpenTimeout, OpenSSL::SSL::SSLError => e
            raise Integrations::Aggregator::TimeoutError, e.message
          end

          private

          attr_reader :reuse_tax_rates, :provider_answered

          def rates_cache
            return unless reuse_tax_rates && DraftTaxRatesCache.enabled?

            @rates_cache ||= DraftTaxRatesCache.new(integration:, payload:)
          end

          def exact_cache
            @exact_cache ||= DraftTaxesCacheService.new(integration:, payload:)
          end

          def exact_taxes
            cache_taxes? ? exact_cache.call { request_taxes } : request_taxes
          end

          # An exact answer for these very amounts beats an estimate, then rates of earlier answers
          # beat a provider call.
          def estimated_taxes
            if cache_taxes? && (body = exact_cache.read)
              track_rates(:exact)
              return body
            end

            unless rates_cache.cacheable?
              track_rates(:skipped)
              return exact_taxes
            end

            if (body = rates_cache.fetch)
              track_rates(:hit)
              return body
            end

            track_rates(:miss)
            body = exact_taxes

            # An exact-cache answer may already be a day old: storing its rates would extend their
            # life past the rates cache TTL.
            rates_cache.store(body) if provider_answered
            body
          end

          def track_rates(outcome)
            Yabeda.tax_providers.draft_tax_rates_cache_total.increment({provider: integration.provider_key, outcome:})
          end

          # NOTE: Throttling happens here, so an answer served from the cache doesn't use up the
          #       provider rate limit.
          def request_taxes
            throttle!(:anrok, :avalara)

            response = trigger_action(payload)
            @provider_answered = true
            parse_response(response)
          end

          # NOTE: Only Anrok draft taxes are cached, see DraftTaxesCacheService.
          def cache_taxes?
            integration.type.to_s == "Integrations::AnrokIntegration"
          end

          def payload
            @payload ||= Integrations::Aggregator::Taxes::Invoices::Payloads::Factory.new_instance(
              integration:,
              invoice:,
              customer:,
              integration_customer:,
              fees: payload_fees
            ).body
          end
        end
      end
    end
  end
end
