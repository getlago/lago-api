# frozen_string_literal: true

class InvoicesTax < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :invoice
  belongs_to :tax
end
