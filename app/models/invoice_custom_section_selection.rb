# frozen_string_literal: true

class InvoiceCustomSectionSelection < ApplicationRecord
  belongs_to :ginvoice_custom_section
  belongs_to :organization, optional: true
  belongs_to :customer, optional: true
end
