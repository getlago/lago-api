# frozen_string_literal: true

class FeesTax < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :fee
  belongs_to :tax
end
