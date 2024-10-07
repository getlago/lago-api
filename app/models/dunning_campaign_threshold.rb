# frozen_string_literal: true

class DunningCampaignThreshold < ApplicationRecord
  include Currencies
  include PaperTrailTraceable

  belongs_to :dunning_campaign

  validates :amount_cents, numericality: {greater_than_or_equal_to: 0}
  validates :currency, inclusion: {in: currency_list}
  validates :currency, uniqueness: {scope: :dunning_campaign_id}
  validates :dunning_campaign_id, presence: true
end

# == Schema Information
#
# Table name: dunning_campaign_thresholds
#
#  id                  :uuid             not null, primary key
#  amount_cents        :bigint           not null
#  currency            :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  dunning_campaign_id :uuid             not null
#
# Indexes
#
#  idx_on_dunning_campaign_id_currency_fbf233b2ae            (dunning_campaign_id,currency) UNIQUE
#  index_dunning_campaign_thresholds_on_dunning_campaign_id  (dunning_campaign_id)
#
# Foreign Keys
#
#  fk_rails_...  (dunning_campaign_id => dunning_campaigns.id)
#
