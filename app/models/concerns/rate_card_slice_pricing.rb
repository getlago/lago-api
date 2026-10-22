# frozen_string_literal: true

# A catalog plan or a contract prices each slice, the pair (product, product
# filter), with at most one applied rate card.
module RateCardSlicePricing
  # The [product_id, product_filter_id] pairs already priced among these products.
  def priced_rate_card_slices(product_ids)
    applied_rate_cards.joins(:rate_card)
      .where(rate_cards: {product_id: product_ids})
      .distinct
      .pluck("rate_cards.product_id", "rate_cards.product_filter_id")
      .to_set
  end

  def rate_card_slice_priced?(rate_card)
    priced_rate_card_slices([rate_card.product_id]).include?([rate_card.product_id, rate_card.product_filter_id])
  end
end
