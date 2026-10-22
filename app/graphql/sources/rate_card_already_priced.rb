# frozen_string_literal: true

module Sources
  # Batches RateCard `alreadyPriced` across a page of cards: one query loads the
  # slices the plan or contract already prices instead of one per card. A plan
  # or contract outside the organization prices nothing, and so does any plan
  # without one (the customer portal reaches rate cards through invoice fees).
  #
  # Usage in GraphQL types:
  #   dataloader.with(Sources::RateCardAlreadyPriced, current_organization, plan_id:).load(rate_card)
  class RateCardAlreadyPriced < GraphQL::Dataloader::Source
    def initialize(organization, plan_id: nil, contract_id: nil)
      @organization = organization
      @plan_id = plan_id
      @contract_id = contract_id
    end

    def fetch(rate_cards)
      owner = find_owner
      return rate_cards.map { false } unless owner

      priced_slices = owner.priced_rate_card_slices(rate_cards.map(&:product_id).uniq)

      rate_cards.map { priced_slices.include?([it.product_id, it.product_filter_id]) }
    end

    private

    def find_owner
      return unless @organization
      return @organization.catalog_plans.find_by(id: @plan_id) if @plan_id

      @organization.contracts.find_by(id: @contract_id)
    end
  end
end
