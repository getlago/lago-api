# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        # Caches the Anrok answer to a draft tax request, keyed on the request itself.
        #
        # Wallet refresh, current usage, invoice preview and draft invoices ask for the same taxes
        # many times while nothing has changed. Taxes can depend on the amount in some
        # jurisdictions, so an answer is only reused for an identical request: the key covers
        # everything sent to the provider (customer id, name and address, tax identification
        # number, currency, dates, and the mapped product code and amount of every line, in
        # order). Any change, down to one cent, is a miss.
        #
        # Two per-line fields are left out of the key. They don't affect taxes, and unsaved usage
        # fees get a new item_key each time they are computed. On a hit they are put back from the
        # current request, since the provider answers lines in the order they were sent.
        #
        # The provider can also change taxes on its own side (a new registration, an exemption
        # certificate, a rate update), which Lago can't see. The TTL bounds how long a draft can
        # lag behind such a change. Finalized invoices never go through this cache.
        class DraftTaxesCacheService < CacheService
          # IMPORTANT: bump when the key or the stored value changes, so old entries are ignored.
          CACHE_KEY_VERSION = "1"
          DEFAULT_TTL = 1.day
          LINE_IDENTIFIERS = %w[item_key item_id].freeze

          def self.ttl
            value = ENV["LAGO_ANROK_DRAFT_TAXES_CACHE_TTL_SECONDS"]
            value.present? ? value.to_i.seconds : DEFAULT_TTL
          end

          def initialize(integration:, payload:)
            @integration = integration
            @payload = payload

            super(expires_in: self.class.ttl)
          end

          # NOTE: A zero TTL turns the cache off entirely, reads included, so entries written before
          #       it was disabled stop being served right away.
          def call
            return yield unless expires_in > 0

            super do
              track(:miss)
              yield
            end
          end

          def cache_key
            [
              "anrok-draft-taxes",
              CACHE_KEY_VERSION,
              integration.id,
              integration.updated_at.to_i,
              payload_digest
            ].join("/")
          end

          private

          attr_reader :integration, :payload

          # Only an answer carrying taxes is reused. A failure goes back to the provider on the next
          # call, so a fixed address or a transient error is picked up right away.
          def cacheable?(body)
            body.is_a?(Hash) && body.dig("succeededInvoices", 0, "fees").present?
          end

          def unwrap(cached)
            track(:hit)

            body = cached.deep_dup
            request_lines = payload.first["fees"]

            body.dig("succeededInvoices", 0, "fees").each_with_index do |line, index|
              line.merge!(request_lines[index].slice(*LINE_IDENTIFIERS)) if request_lines[index]
            end

            body
          end

          def payload_digest
            Digest::SHA256.hexdigest(key_payload.to_json)
          end

          def key_payload
            payload.map do |transaction|
              transaction.merge("fees" => transaction["fees"].map { |line| line.except(*LINE_IDENTIFIERS) })
            end
          end

          def track(outcome)
            Yabeda.tax_providers.draft_taxes_cache_total.increment({provider: "anrok", outcome:})
          end
        end
      end
    end
  end
end
