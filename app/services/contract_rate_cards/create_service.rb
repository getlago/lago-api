# frozen_string_literal: true

module ContractRateCards
  # Attaches a rate card to a contract, pricing it through its own rate
  # phases. Authoring is pending-only: once the contract is active its cards
  # are signed. The card carries the billing lifecycle (day-grained window,
  # anchor, clock); a plan-less contract prices entirely through direct cards.
  class CreateService < BaseService
    Result = BaseResult[:contract_rate_card]

    def initialize(contract:, params:)
      @contract = contract
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      unless contract.editable?
        return result.single_validation_failure!(field: :contract, error_code: "contract_locked")
      end

      # Date column: a malformed value would silently cast to nil instead of
      # failing, so the format is rejected explicitly.
      if params[:billing_anchor_date].present? && !Utils::Datetime.valid_format?(params[:billing_anchor_date])
        return result.single_validation_failure!(field: :billing_anchor_date, error_code: "value_is_invalid")
      end

      rate_card = organization.rate_cards.find_by(code: params[:rate_card_code])
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      # Fees bill in the card currency and the invoice in the contract's
      # currency (its plan's, or the customer's for a plan-less contract); a
      # mismatch must fail at configuration time, not on the first invoice.
      if rate_card.currency != contract.currency
        return result.single_validation_failure!(field: :currency, error_code: "currency_does_not_match")
      end

      contract.with_lock do
        # One card per pricing slice: a contract may hold several cards of the
        # same item only when they cover different filter slices (default + EU).
        if slice_already_priced?(rate_card)
          return result.single_validation_failure!(field: :rate_card, error_code: slice_error_code(rate_card))
        end

        contract_rate_card = contract.applied_rate_cards.create!(
          organization:,
          rate_card:,
          units: params[:units],
          **contract.default_rate_card_lifecycle(billing_anchor_date: params[:billing_anchor_date].presence)
        )

        # Phases can be authored atomically with the card: a provided sequence
        # goes through the same validations as the single-phase ops (an
        # explicit empty list is rejected there) and a failure rolls the whole
        # create back. Omitted or null, the card starts on a single default
        # terminal phase.
        if params.key?(:rate_phases) && !params[:rate_phases].nil?
          RatePhases::ReplaceService.call!(contract_rate_card:, phases_params: params[:rate_phases])
        else
          RatePhases::CreateService.call!(contract_rate_card:, params: {code: "default", position: 1})
        end

        result.contract_rate_card = contract_rate_card
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :contract, :params

    def slice_error_code(rate_card)
      if rate_card.product_filter_id
        "product_filter_already_priced"
      else
        "product_already_priced"
      end
    end

    def slice_already_priced?(rate_card)
      contract.applied_rate_cards.current_and_scheduled.joins(:rate_card).exists?(
        rate_cards: {
          product_id: rate_card.product_id,
          product_filter_id: rate_card.product_filter_id
        }
      )
    end

    def organization
      contract.organization
    end
  end
end
